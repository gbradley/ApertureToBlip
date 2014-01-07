//
//  API.m
//

#import "API.h"
#import "NSString+URLEncoding.h"

@implementation API

@synthesize key, secret, userToken, userSecret, displayName, asyncData;

// create instance
- (id) initWithKey:(NSString *) apiKey secret:(NSString *) apiSecret {
    
    self.key = apiKey;
    self.secret = apiSecret;
    timestampOffset = 0;
    timestampOffsetFetched = NO;
    asyncInProgress = NO;
    
    return self;
}

- (NSString *) buildUrlString:(NSString *)resource {
    // ensure requests to the token resource are over https
    NSString *protocol;
    if (([resource isEqualToString:@"token"])) {
        protocol = @"https";
    } else {
        protocol = @"http";
    }
    
    // generate the first part of the URL string
    return [NSString stringWithFormat:@"%@://api.blipfoto.com/v3/%@.json", protocol, resource];
}

- (BOOL) request:(NSString *) method resource:(NSString *) resource params:(NSMutableDictionary *) params authType:(APIAuthType) auth onSuccess:(void (^)(NSDictionary *response)) success onFailure:(void (^)(NSError *error)) failure {
    
    // generate the first part of the URL string
    NSString *urlString = [self buildUrlString:resource];
    
    NSMutableData *requestBody = nil;
    NSString *contentType = nil;
    NSData *jpegData = nil;
    
    // add the default parameters
    params = [self addDefaultParams:params authType:auth];
    
    if ([method isEqualToString:@"get"]) {
        // add the parameters in the query string
        urlString = [NSString stringWithFormat:@"%@?%@", urlString, [self buildQueryString:params]];
    } else {
        
        // determine if there's image data in the params
        NSString *imgName;
        NSArray *keys = [params allKeys];
        for (int i = 0; i < [keys count]; i++) {
            if ([[params objectForKey:[keys objectAtIndex:i]] isKindOfClass:[NSData class]]) {
                imgName = [keys objectAtIndex:i];
                jpegData = [params objectForKey:[keys objectAtIndex:i]];
                [params removeObjectForKey:imgName];
                break;
            }
        }
        
        if (jpegData == nil) {
            
            // construct a standard form-encoded request
            NSString *bodystring = [self buildQueryString:params];
            requestBody = [NSData dataWithBytes:[bodystring UTF8String] length: [bodystring length]];
            contentType = @"application/x-www-form-urlencoded";
        } else {
            
            // construct the body manually
            requestBody = [[NSMutableData alloc] initWithLength:0];
            NSString *boundary = @"---------------------------14737809831466499882746641449";
            contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
            
            // add the image
            [requestBody appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
            [requestBody appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"upload.jpg\"\r\n", imgName] dataUsingEncoding:NSUTF8StringEncoding]];
            [requestBody appendData:[@"Content-Type: application/octet-stream\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
            
            [requestBody appendData:jpegData];
            
            // add the other POST params
            keys = [params allKeys];
            int l = [keys count];
            for (int i=0; i<l; i++) {
                [requestBody appendData:[[NSString stringWithFormat:@"\r\n--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
                [requestBody appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", [keys objectAtIndex:i]] dataUsingEncoding:NSUTF8StringEncoding]];
                [requestBody appendData:[[params objectForKey:[keys objectAtIndex:i]] dataUsingEncoding:NSUTF8StringEncoding]];
            }
            
            [requestBody appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
            
        }
    }
    
    // construct the request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    request.HTTPMethod = [method uppercaseString];
    request.HTTPBody = requestBody;
    
    // add any headers
    if (contentType != nil) {
        [request setValue:contentType forHTTPHeaderField:@"Content-Type"];
    }
    
    // Image uploads should be cancellable, so do them asynchronously
    SEL selector = jpegData == nil ? @selector(executeSynchronousRequest:) : @selector(executeAsynchronousRequest:);
    
    NSMutableArray *connectionInfo = [NSMutableArray arrayWithObjects:request, [NSNull null], [success copy], [failure copy], nil];
    [self performSelectorInBackground:selector withObject:connectionInfo];
    
    // we've done [block copy] to transfer ownership to the array, so destroy the original references
    success = nil;
    failure = nil;
    
    return YES;
}



/* PRIVATE */

// add default parameters including auth
- (NSMutableDictionary *) addDefaultParams:(NSMutableDictionary *) params authType:(APIAuthType) auth {
    if (params == nil) {
        params = [NSMutableDictionary dictionaryWithCapacity:0];
    }
    [params setObject:self.key forKey:@"api_key"];
    
    // add authentication parameters if requested
    if (auth){
        
        int ts = [self generateTimestamp];
        [params setObject:[NSString stringWithFormat:@"%d", ts] forKey:@"timestamp"];
        
        NSString *nonce = [self generateNonce];
        [params setObject:nonce forKey:@"nonce"];
        
        NSString *signature;
        if (auth == APIAuthTypeApplication) {
            signature = [self MD5:[NSString stringWithFormat:@"%d%@%@", ts, nonce, self.secret]];
        } else if (auth == APIAuthTypeUser) {
            signature = [self MD5:[NSString stringWithFormat:@"%d%@%@%@", ts, nonce, self.userToken, self.userSecret]];
            [params setObject:self.userToken forKey:@"token"];
        }
        [params setObject:signature forKey:@"signature"];
    }
    
    return params;
}

// create query string from parameters
- (NSString *) buildQueryString:(NSMutableDictionary *) params {
	
	NSMutableString *qs = [[NSMutableString alloc] init];
    
	NSArray *keys = [params allKeys];
	int l = [keys count];
	for (int i=0; i<l; i++) {
		[qs appendFormat:@"&%@=%@", [keys objectAtIndex:i], [NSString URLEncodedStringFromString:[params objectForKey:[keys objectAtIndex:i]]]];
	}
    
	return [NSString stringWithString:qs];
}

// execute synchronous request in background
- (void) executeSynchronousRequest:(NSMutableArray *) connectionInfo {
    
    @autoreleasepool {
        
        NSURLRequest *request = [connectionInfo objectAtIndex:0];
        NSURLResponse *response;
        NSError *error;
        NSJSONSerialization *json;
        
        NSData *responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
        
        if (!error) {
            json = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:&error];
        }
        
        [connectionInfo replaceObjectAtIndex:0 withObject:json == nil ? [NSNull null] : json];
        
        [self performSelectorOnMainThread:@selector(requestCompleted:) withObject:connectionInfo waitUntilDone:NO];
    }
}

// execute asynchronous request in background
- (void) executeAsynchronousRequest:(NSMutableArray *) connectionInfo {
    
    @autoreleasepool {
        
        self.asyncData = [[NSMutableData alloc] initWithLength:0];
        
        // store these so they persist during delegate calls
        onasyncsuccess = [connectionInfo objectAtIndex:2];
        onasyncfailure = [connectionInfo objectAtIndex:3];
        
        asyncConn = [[NSURLConnection alloc] initWithRequest:[connectionInfo objectAtIndex:0] delegate:self startImmediately:YES];
        // keep thread alive during async request, otherwise delegates don't get called
        asyncInProgress = YES;
        while(asyncInProgress && [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]) {
        }
    }
}

// async response received in background
- (void) asyncResponseReceived:(NSData *) responseData error:(NSError *)error {
    
    // this is wonky as we can't simply pass nil inside the array
    NSDictionary *response;
    NSMutableArray *connectionInfo;
    if (responseData) {
        NSError *parseError;
        response = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:&parseError];
        if (parseError) {
            connectionInfo = [NSMutableArray arrayWithObjects:[NSNull null], parseError, onasyncsuccess, onasyncfailure, nil];
        } else {
            connectionInfo = [NSMutableArray arrayWithObjects:response, [NSNull null], onasyncsuccess, onasyncfailure, nil];
        }
    } else {
        connectionInfo = [NSMutableArray arrayWithObjects:[NSNull null], error, onasyncsuccess, onasyncfailure, nil];
    }
    
    [self performSelectorOnMainThread:@selector(requestCompleted:) withObject:connectionInfo waitUntilDone:NO];
}

// cancel the current async request
- (BOOL) cancelCurrentRequest {
    if (asyncInProgress) {
        [asyncConn cancel];
        asyncInProgress = NO;
        return YES;
    } else {
        return NO;
    }
}

// connection done and returned to main thread; parse response
- (void) requestCompleted:(NSMutableArray *) connectionInfo {
    
    id json = [connectionInfo objectAtIndex:0];
    NSError *error = [connectionInfo objectAtIndex:1];
    
    void (^onsuccess)() = nil;
    void (^onfailure)() = nil;
    int args = [connectionInfo count];
    
    if (args == 4) {
        onsuccess = [connectionInfo objectAtIndex:2];
        onfailure = [connectionInfo objectAtIndex:3];
    } else if (args == 3) {
        onsuccess = [connectionInfo objectAtIndex:2];
    }
    
    if (onsuccess || onfailure) {
        
        if (json == (id)[NSNull null]) {
            if (error == (id)[NSNull null]) {
                error = [[NSError alloc] initWithDomain:@"com.blipfoto.errorDomain" code:-1 userInfo:[NSDictionary dictionaryWithObject:@"Couldn't complete the request" forKey:NSLocalizedDescriptionKey]];
            }
        } else {
            id jsonError = [json objectForKey:@"error"];
            if (jsonError != [NSNull null]) {
                error = [[NSError alloc] initWithDomain:@"com.blipfoto.errorDomain" code:[[jsonError objectForKey:@"code"] intValue] userInfo:[NSDictionary dictionaryWithObject:[jsonError objectForKey:@"message"] forKey:NSLocalizedDescriptionKey]];
            }
        }
        
        if (error != (id)[NSNull null]) {
            if (onfailure) {
                onfailure(error);
            }
        } else {
            if (onsuccess) {
                onsuccess(json);
            }
        }
    }
}

// generate an MD5 hash
- (NSString *) MD5:(NSString *) str {
	const char *cStr = [str UTF8String];
	unsigned char result[CC_MD5_DIGEST_LENGTH];
	CC_MD5(cStr, strlen(cStr), result);
	return [NSString stringWithFormat:
			@"%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X",
			result[0], result[1], result[2], result[3], result[4], result[5], result[6], result[7],
			result[8], result[9], result[10], result[11], result[12], result[13], result[14], result[15]
			];
}

// generate a random 32-bit string
- (NSString *) generateNonce {
    
    NSString *letters = @"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    NSMutableString *str = [NSMutableString stringWithCapacity: 32];
    
    for (int i=0; i<32; i++) {
        [str appendFormat: @"%C", [letters characterAtIndex: arc4random() % [letters length]]];
    }
	
    return [NSString stringWithString:str];
}

// return the timestamp including the stored offset
- (int) generateTimestamp {
    
    int deviceTime = (int)[[NSDate date] timeIntervalSince1970];
    
    if (!timestampOffsetFetched) {
        
        // fetch the API time
        NSString *urlString = [self buildUrlString:@"time"];
        NSString *queryString = [self buildQueryString:[self addDefaultParams:nil authType:APIAuthTypeNone]];
        NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@?%@", urlString, queryString]]];
        
        NSURLResponse *response;
        NSError *error;
        NSJSONSerialization *json;
        
        NSData *responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
        if (!error) {
            json = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:&error];
            if (json) {
                timestampOffset = [[[(NSDictionary *)json objectForKey:@"data"] objectForKey:@"timestamp"] intValue] - deviceTime;
                timestampOffsetFetched = YES;
            }
        }
        
    }
    
	return deviceTime + timestampOffset;
}

/* Async URLConnection delegate methods */

- (void) connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [self.asyncData appendData:data];
}

- (void) connectionDidFinishLoading:(NSURLConnection *)connection {
	asyncInProgress = NO;
	[self asyncResponseReceived:self.asyncData error:nil];
}

- (void) connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
	asyncInProgress = NO;
    [self asyncResponseReceived:nil error:error];
}

- (void) connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
	if (self.asyncData!=nil && ![self.asyncData isEqual:[NSNull null]]){
		[self.asyncData setLength:0];
	}
}

- (void)connection:(NSURLConnection *)connection didSendBodyData:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite {
    float progress = (float)totalBytesWritten / (float)totalBytesExpectedToWrite;
    [self performSelectorOnMainThread:@selector(postProgressNotification:) withObject:[NSNotification notificationWithName:@"PublishProgressUpdated" object:[NSNumber numberWithFloat:progress]] waitUntilDone:NO];
}

- (void) postProgressNotification:(NSNotification *) notification {
    [[NSNotificationCenter defaultCenter] postNotification:notification];
}

@end
