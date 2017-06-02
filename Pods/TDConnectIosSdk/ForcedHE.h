#import <Foundation/Foundation.h>

BOOL isWifiEnabled();
BOOL isCellularEnabled();

BOOL shouldFetchThroughCellular(NSString *url);
NSDictionary *openUrlThroughCellular(NSString *url);

void testIP(NSString *iface);

void initForcedHE();



