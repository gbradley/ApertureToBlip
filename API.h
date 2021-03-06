//
//  API.h
//
//  Once you've created an instance, you'll probably only
//  need to use the request:... method, which accepts
//  success and failure callback blocks. I should probably
//  rewrite this as a singleton.

#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>

@interface API : NSObject {
    
    NSString *key;
	NSString *secret;
    NSString *userToken;
    NSString *userSecret;
    NSString *displayName;
    
    int timestampOffset;
    BOOL timestampOffsetFetched;
    
    NSURLConnection *asyncConn;
    NSMutableData *asyncData;
    void (^onasyncsuccess)();
    void (^onasyncfailure)();
    BOOL asyncInProgress;
    
}

typedef enum {
    APIAuthTypeNone           = 0,
    APIAuthTypeApplication    = 1,
    APIAuthTypeUser           = 2
} APIAuthType;

@property (nonatomic, retain) NSString *key;
@property (nonatomic, retain) NSString *secret;
@property (nonatomic, retain) NSString *userToken;
@property (nonatomic, retain) NSString *userSecret;
@property (nonatomic, retain) NSString *displayName;
@property (nonatomic, retain) NSMutableData *asyncData;


/* Public */

// create a new instance
- (id) initWithKey:(NSString *) apiKey secret:(NSString *) apiSecret;

// issue a new request
- (BOOL) request:(NSString *) method resource:(NSString *) resource params:(NSMutableDictionary *) params authType:(APIAuthType) auth onSuccess:(void (^)(NSDictionary *response)) success onFailure:(void (^)(NSError *error)) failure;

// cancel the current request (async only)
- (BOOL) cancelCurrentRequest;

/* Private */

// add default parameters including auth
- (NSMutableDictionary *) addDefaultParams:(NSMutableDictionary *) params authType:(APIAuthType) auth;

- (NSString *) buildUrlString:(NSString *) resource;

// create query string from parameters
- (NSString *) buildQueryString:(NSMutableDictionary *) params;

// execute synchronous request in background
- (void) executeSynchronousRequest:(NSMutableArray *) connectionInfo;

// execute asynchronous request in background
- (void) executeAsynchronousRequest:(NSMutableArray *) connectionInfo;

// async response received in background
- (void) asyncResponseReceived:(NSData *) responseData error:(NSError *) error;

// connection done and returned to main thread
- (void) requestCompleted:(NSMutableArray *) connectionInfo;

// generate an MD5 hash
- (NSString *) MD5:(NSString *) str;

// generate a random 32-len string
- (NSString *) generateNonce;

// return the timestamp including the stored offset
- (int) generateTimestamp;

@end
