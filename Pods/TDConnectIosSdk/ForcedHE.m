#import "ForcedHE.h"

#import <arpa/inet.h> // For AF_INET, etc.
#import <ifaddrs.h> // For getifaddrs()
#import <net/if.h> // For IFF_LOOPBACK
#import <netinet/in.h>
#import <ifaddrs.h>
#import <netdb.h>

#include <curl/curl.h>

int MAX_REDIRECTS_TO_FOLLOW_FOR_HE = 5;

void initForcedHE() {
    curl_global_init(CURL_GLOBAL_DEFAULT);
}


BOOL checkInterface(NSString *iface) {
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    NSInteger success = getifaddrs(&interfaces);
    if (success == 0) {
        // Loop through linked list of interfaces
        temp_addr = interfaces;
        while(temp_addr != NULL) {
            if(temp_addr->ifa_addr->sa_family == AF_INET) {
                // Get NSString from C String
                NSString* ifaName = [NSString stringWithUTF8String:temp_addr->ifa_name];
                NSString* address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *) temp_addr->ifa_addr)->sin_addr)];
                NSString* mask = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *) temp_addr->ifa_netmask)->sin_addr)];
                NSString* gateway = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *) temp_addr->ifa_dstaddr)->sin_addr)];
                NSLog(@"%@;%@;%@;%@",ifaName,address,mask,gateway);
                //                NSString *messageString = [NSString stringWithFormat:@"%@;%@;%@;%@",ifaName,address,mask,gateway];
                //
                //                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Wait"
                //                                                            message:messageString delegate:self cancelButtonTitle:@"Delete" otherButtonTitles:@"Cancel", nil];
                //                [alert show];
                if ([ifaName isEqualToString:iface]) {
                    return true;
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    return false;
}

BOOL isWifiEnabled() {
    return checkInterface(@"en0");
}

BOOL isCellularEnabled() {
    return checkInterface(@"pdp_ip0");
}


BOOL shouldFetchThroughCellular(NSString *url) {
    BOOL result = false;

    NSURL* urlParsed = [NSURL URLWithString:url];
    NSString *hostName = urlParsed.host;

    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = PF_UNSPEC;        // PF_INET if you want only IPv4 addresses
    hints.ai_protocol = IPPROTO_TCP;

    struct addrinfo *addrs, *addr;

    getaddrinfo([hostName cStringUsingEncoding:NSUTF8StringEncoding], NULL, &hints, &addrs);
    for (addr = addrs; addr; addr = addr->ai_next) {
        char host[NI_MAXHOST];
        getnameinfo(addr->ai_addr, addr->ai_addrlen, host, sizeof(host), NULL, 0, NI_NUMERICHOST);
        // printf("%s\n", host);
        // NSLog(@"%@", url);
        if (strcmp(host, "52.16.250.20") == 0) {
            result = true;
        }
        if (strcmp(host, "54.77.158.173") == 0) {
            result = true;
        }
    }
    freeaddrinfo(addrs);

    return result;
}

static curl_socket_t opensocket(void *clientp,
                                curlsocktype purpose,
                                struct curl_sockaddr *address)
{
    curl_socket_t sockfd;
    sockfd = *(curl_socket_t *)clientp;
    /* the actual externally set socket is passed in via the OPENSOCKETDATA
     option */
    return sockfd;
}

static int sockopt_callback(void *clientp, curl_socket_t curlfd,
                            curlsocktype purpose)
{
    /* This return code was added in libcurl 7.21.5 */
    return CURL_SOCKOPT_OK;
}

struct MemoryStruct {
    char *memory;
    size_t size;
};

static size_t WriteMemoryCallback(void *contents, size_t size, size_t nmemb, void *userp) {
    size_t realsize = size * nmemb;
    struct MemoryStruct *mem = (struct MemoryStruct *)userp;

    mem->memory = realloc(mem->memory, mem->size + realsize + 1);
    if (mem->memory == NULL) {
        /* out of memory! */
        exit(EXIT_FAILURE);
    }

    memcpy(&(mem->memory[mem->size]), contents, realsize);
    mem->size += realsize;
    mem->memory[mem->size] = 0;

    return realsize;
}

NSDictionary* openUrlThroughCellular(NSString *url) {
    NSLog(@"%@", url);

    BOOL useCellular = true;
    CURL *curl;
    NSString *newUrl = url;
    NSDictionary *resDict = @{};
    int attempts = 0;

    do {
        curl = curl_easy_init();
        if (!curl) {
            return resDict;
        }

        curl_easy_setopt(curl, CURLOPT_OPENSOCKETFUNCTION, opensocket);
        curl_easy_setopt(curl, CURLOPT_SOCKOPTFUNCTION, sockopt_callback);
        curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 0L);
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, WriteMemoryCallback);

        //socket
        int socketfd = socket(AF_INET, SOCK_STREAM, 0);
        int interfaceIndex;
        if (useCellular) {
            interfaceIndex = if_nametoindex("pdp_ip0");
        } else {
            interfaceIndex = if_nametoindex("en0");
        }
        setsockopt(socketfd, IPPROTO_IP, IP_BOUND_IF, &interfaceIndex, sizeof(interfaceIndex));
        curl_easy_setopt(curl, CURLOPT_OPENSOCKETDATA, &socketfd);


        // memory
        struct MemoryStruct chunk;
        chunk.memory = malloc(1);
        chunk.size = 0;
        curl_easy_setopt(curl, CURLOPT_WRITEDATA, (void *)&chunk);

        // request
        curl_easy_setopt(curl, CURLOPT_URL, [newUrl UTF8String]);
        CURLcode res = curl_easy_perform(curl);
        attempts += 1;

        // free memory
        NSData *data = [NSData dataWithBytes:chunk.memory length:chunk.size];
        if(chunk.memory) {
            free(chunk.memory);
            chunk.memory = NULL;
        }

        if (res != CURLE_OK) {
            NSLog(@"curl_easy_perform() failed: %s\n", curl_easy_strerror(res));
            break;
        }

        long responseCode;
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &responseCode);

        if (responseCode != 303 && responseCode != 302 && responseCode != 301) {
            char *pszContentType;
            curl_easy_getinfo(curl, CURLINFO_CONTENT_TYPE, &pszContentType);
            resDict =  @{@"responseCode" : [NSNumber numberWithLong:responseCode], @"contentType" : [NSString stringWithUTF8String:pszContentType], @"data": data};
            break;
        }

        char *location;
        curl_easy_getinfo(curl, CURLINFO_REDIRECT_URL, &location);
        newUrl = [NSString stringWithUTF8String:location];

        if((res == CURLE_OK) && location) {
            useCellular = responseCode == 302 ? true : shouldFetchThroughCellular(newUrl);
        } else {
            break;
        }

        if (attempts > MAX_REDIRECTS_TO_FOLLOW_FOR_HE) {
            break;
        }

        curl_easy_cleanup(curl);
    } while (1);

    curl_easy_cleanup(curl);
    return resDict;
}

void testIP(NSString *iface) {
    CURL *curl = curl_easy_init();
    if(curl) {
        int socketfd = socket(AF_INET, SOCK_STREAM, 0);
        int index = if_nametoindex( [iface cStringUsingEncoding:NSUTF8StringEncoding]);
        setsockopt(socketfd, IPPROTO_IP, IP_BOUND_IF, &index, sizeof(index));

        curl_easy_setopt(curl, CURLOPT_OPENSOCKETFUNCTION, opensocket);
        curl_easy_setopt(curl, CURLOPT_OPENSOCKETDATA, &socketfd);
        curl_easy_setopt(curl, CURLOPT_SOCKOPTFUNCTION, sockopt_callback);
        curl_easy_setopt(curl, CURLOPT_URL, "http://api.ipify.org");
        CURLcode res = curl_easy_perform(curl);
        curl_easy_cleanup(curl);
    }
}