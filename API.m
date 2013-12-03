//
//  API.m
//  Blip for iPone
//
//  Created by Graham Bradley on 10/08/2012.
//  Copyright (c) 2012 Blipfoto. All rights reserved.
//

#import "API.h"
#import "AppDelegate.h"
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
    
    prefixDefault = @"http://api.blipfoto.com/v3/";
    
    return self;
}

- (BOOL) request:(NSString *) method resource:(NSString *) resource params:(NSMutableDictionary *) params authType:(APIAuthType) auth onSuccess:(void (^)(NSDictionary *response)) success onFailure:(void (^)(NSError *error)) failure {
    
    
    NSString *format = @"json";
    if ([[params allKeys] containsObject:@"format"]){
        format = [params objectForKey:@"format"];
        [params removeObjectForKey:@"format"];
    }
    
    // for live site, ensure requests to the trusttoken resource are over SSL
    NSString *prefix;
    if (([resource isEqualToString:@"trusttoken"] || [resource isEqualToString:@"account"]) && [prefixDefault isEqualToString:@"http://api.blipfoto.com/v3/"]){
        prefix = @"https://api.blipfoto.com/v3/";
    } else {
        prefix = [NSString stringWithString:prefixDefault];
    }
    
    // generate the first part of the URL string
    NSString *urlString = [NSString stringWithFormat:@"%@%@.%@", prefix, resource, format];
    
    NSMutableData *requestBody = nil;
    NSString *contentType = nil;
    NSData *jpegData = nil;
    
    // add the default parameters
    params = [self addDefaultParams:params authType:auth];
    
    if ([method isEqualToString:@"get"]){
        // add the parameters to the URL as a query string
        urlString = [NSString stringWithFormat:@"%@?%@", urlString, [self buildQueryString:params]];
    } else {
        
        // determine if there's image data in the params (either UIImage or contents of file marked by @)
        NSString *imgName;
        NSArray *keys = [params allKeys];
        for (int i = 0; i < [keys count]; i++){
            if ([[params objectForKey:[keys objectAtIndex:i]] isKindOfClass:[UIImage class]]){
                imgName = [keys objectAtIndex:i];
                jpegData = UIImageJPEGRepresentation([params objectForKey:imgName], 100);
                [params removeObjectForKey:imgName];
                break;
            } else if ([[[keys objectAtIndex:i] substringToIndex:1] isEqualToString:@"@"]){
                imgName = [keys objectAtIndex:i];
                jpegData = [NSData dataWithContentsOfFile:[params objectForKey:imgName]];
                [params removeObjectForKey:imgName];
                imgName = [imgName substringFromIndex:1];
            }
        }
        
        if (jpegData==nil){		// construct a standard form-encoded request
            
            NSMutableString *bodystring = [self buildQueryString:params];
            requestBody = [NSData dataWithBytes:[bodystring UTF8String] length: [bodystring length]];
            contentType = @"application/x-www-form-urlencoded";
        } else {
            
            requestBody = [[NSMutableData alloc] initWithLength:0];
            NSString *boundary = @"---------------------------14737809831466499882746641449";
            contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
            
            // add the image
            [requestBody appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
            [requestBody appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"upload.jpg\"\r\n", imgName] dataUsingEncoding:NSUTF8StringEncoding]];
            [requestBody appendData:[@"Content-Type: application/octet-stream\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
            
            [requestBody appendData:jpegData];
            
            /*int orient=jpeg.imageOrientation;
             if (orient > 0){
             [requestBody appendData:[[NSString stringWithFormat:@"\r\n--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
             [requestBody appendData:[@"Content-Disposition: form-data; name=\"transform\"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
             if (orient==1) [requestBody appendData:[@"rotate:180" dataUsingEncoding:NSUTF8StringEncoding]];
             else if (orient==2) [requestBody appendData:[@"rotate:270" dataUsingEncoding:NSUTF8StringEncoding]];
             else if (orient==3) [requestBody appendData:[@"rotate:90" dataUsingEncoding:NSUTF8StringEncoding]];
             }*/
            
            // add the other POST params
            keys = [params allKeys];
            int l = [keys count];
            for (int i=0; i<l; i++){
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
    if (contentType != nil){
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
    if (params == nil){
        params = [NSMutableDictionary dictionaryWithCapacity:0];
    }
    [params setObject:self.key forKey:@"api_key"];
    
    // add authentication parameters if requested (AND token is available)
    if (auth){
        
        int ts = [self generateTimestamp];
        NSString *nonce = [self generateNonce];
        NSString *signature;
        
        
        [params setObject:[NSString stringWithFormat:@"%d", ts] forKey:@"timestamp"];
        [params setObject:nonce forKey:@"nonce"];
        
        if (auth==APIAuthTypeApplication){
            signature = [self MD5:[NSString stringWithFormat:@"%d%@%@", ts, nonce, self.secret]];
        }
        else if (auth==APIAuthTypeUser){
            
            /**
             * In 3.1 we introduced the concept of user secrets, which we can use to sign requests instead of app secrets.
             * The benefit here being that if the app secret is revealed, we can regenerate a new secret without invalidating
             * the users who are currently signed in. So use the user secret if there is one, otherwise use the app secret.
             */
            
            NSString *secretValue;
            if ((id)self.userSecret == [NSNull null] || [self.userSecret isEqualToString:@""]){
                secretValue = self.secret;
            } else {
                secretValue = self.userSecret;
            }
            signature = [self MD5:[NSString stringWithFormat:@"%d%@%@%@", ts, nonce, self.userToken, secretValue]];
            [params setObject:self.userToken forKey:@"token"];
        }
        [params setObject:signature forKey:@"signature"];
    }
    
    // add the device ID (needed for all user auth plus also for trusttoken / account resources)
    [params setObject:[self getDeviceID] forKey:@"device_id"];
    
    return params;
}

// create query string from parameters
- (NSMutableString *) buildQueryString:(NSMutableDictionary *) params {
	
	NSMutableString *qs = [[NSMutableString alloc] init];
    
	NSArray *keys = [params allKeys];
	int l = [keys count];
	for (int i=0; i<l; i++){
		[qs appendFormat:@"&%@=%@", [keys objectAtIndex:i], [NSString URLEncodedStringFromString:[params objectForKey:[keys objectAtIndex:i]]]];
	}
    
	return qs;
}

// execute synchronous request in background
- (void) executeSynchronousRequest:(NSMutableArray *) connectionInfo {
    
    @autoreleasepool {
        
        NSURLRequest *request = [connectionInfo objectAtIndex:0];
        NSURLResponse *response;
        NSError *error;
        NSJSONSerialization *json;
        
        NSData *responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
        
        if (!error){
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
        DLog(@"%@", asyncConn);
        // keep thread alive during async request, otherwise delegates don't get called
        asyncInProgress = YES;
        while(asyncInProgress && [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]){
        }
    }
}

// async response received in background
- (void) asyncResponseReceived:(NSData *) responseData error:(NSError *)error {
    
    // this is wonky as we can't simply pass nil inside the array
    NSDictionary *response;
    NSArray *connectionInfo;
    if (responseData){
        NSError *parseError;
        response = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:&parseError];
        if (parseError){
            connectionInfo = [NSArray arrayWithObjects:[NSNull null], parseError, onasyncsuccess, onasyncfailure, nil];
        } else {
            connectionInfo = [NSArray arrayWithObjects:response, [NSNull null], onasyncsuccess, onasyncfailure, nil];
        }
    }
    else {
        connectionInfo = [NSArray arrayWithObjects:[NSNull null], error, onasyncsuccess, onasyncfailure, nil];
    }
    
    [self performSelectorOnMainThread:@selector(requestCompleted:) withObject:connectionInfo waitUntilDone:NO];
}

// cancel the current async request
- (BOOL) cancelCurrentRequest {
    if (asyncInProgress){
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
    
    if (args == 4){
        onsuccess = [connectionInfo objectAtIndex:2];
        onfailure = [connectionInfo objectAtIndex:3];
    } else if (args == 3){
        onsuccess = [connectionInfo objectAtIndex:2];
    }
    
    if (onsuccess || onfailure){
        
        if (json == (id)[NSNull null]){
            if (error == (id)[NSNull null]){
                error = [[NSError alloc] initWithDomain:@"com.blipfoto.errorDomain" code:-1 userInfo:[NSDictionary dictionaryWithObject:@"Couldn't complete the request" forKey:NSLocalizedDescriptionKey]];
            }
        }
        else {
            id jsonError = [json objectForKey:@"error"];
            if (jsonError != [NSNull null]){
                
                error = [[NSError alloc] initWithDomain:@"com.blipfoto.errorDomain" code:[[jsonError objectForKey:@"code"] intValue] userInfo:[NSDictionary dictionaryWithObject:[jsonError objectForKey:@"message"] forKey:NSLocalizedDescriptionKey]];
            }
        }
        
        if (error != (id)[NSNull null]){
            if (onfailure){
                onfailure(error);
            }
        } else {
            if (onsuccess){
                onsuccess(json);
            }
        }
    }
}

// generate an MD5 hash
- (NSString *) MD5:(NSString *) str {
	const char *cStr = [str UTF8String];
	unsigned char result[CC_MD5_DIGEST_LENGTH];
	CC_MD5( cStr, strlen(cStr), result );
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
	//int t = (int)[[NSDate date] timeIntervalSince1970];
	//DLog(@"timestamp is %d + %d = %d", t, timestampOffset, t+timestampOffset);
    
    int deviceTime = (int)[[NSDate date] timeIntervalSince1970];
    
    if (!timestampOffsetFetched){
        
        // we need to fetch the API time (doing it synchronously which is bad).
        
        NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@time.json?%@", prefixDefault, [self buildQueryString:[self addDefaultParams:nil authType:APIAuthTypeNone]]]]];
        NSURLResponse *response;
        NSError *error;
        NSJSONSerialization *json;
        NSData *responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
        if (!error){
            json = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:&error];
            if (json){
                timestampOffset = [[[(NSDictionary *)json objectForKey:@"data"] objectForKey:@"timestamp"] intValue] - deviceTime;
                timestampOffsetFetched = YES;
            }
        }
        
    }
    
	return deviceTime + timestampOffset;
}

// return the difference in hours between GMT and the local timezone, taking BST daylight savings into account.
- (int) generateTimezoneOffset {
    return (int) round(([[NSTimeZone localTimeZone] secondsFromGMT] - [[NSTimeZone timeZoneWithAbbreviation:@"BST"] daylightSavingTimeOffsetForDate:[NSDate date]]) / (60 * 60));
}

// return a device ID (hashed with MD5), either from the prefs or UUID method for the version of iOS.
- (NSString *) getDeviceID {
    
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    NSString *deviceID =[prefs objectForKey:@"auth.deviceID"];
    if (deviceID != nil){
        return deviceID;
    } else {
        
        UIDevice *device = [UIDevice currentDevice];
        if ([device respondsToSelector:@selector(identifierForVendor)]){
            deviceID = [[device identifierForVendor] UUIDString];
        }
        else if ([NSUUID class]){
            deviceID = [[[NSUUID alloc] init] UUIDString];
        } else {
            CFUUIDRef theUUID = CFUUIDCreate(NULL);
            CFStringRef str = CFUUIDCreateString(NULL, theUUID);
            deviceID = [NSString stringWithString:(__bridge NSString *)str];
            CFRelease(theUUID);
            CFRelease(str);
        }
        [prefs setObject:[self MD5:deviceID] forKey:@"auth.deviceID"];
    }
    return deviceID;
}


/* Async URLConnection delegate methods */

- (void) connection:(NSURLConnection *)connection didReceiveData:(NSData *)data{
    [self.asyncData appendData:data];
}

- (void) connectionDidFinishLoading:(NSURLConnection *)connection{
    DLog(@"connection finished loading");
	asyncInProgress = NO;
	[self asyncResponseReceived:self.asyncData error:nil];
}

- (void) connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    DLog(@"connection failed with error %@", error);
	asyncInProgress = NO;
    [self asyncResponseReceived:nil error:error];
}

- (void) connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response{
    DLog(@"connection received response");
	if (self.asyncData!=nil && ![self.asyncData isEqual:[NSNull null]]){
		[self.asyncData setLength:0];
	}
}

- (void)connection:(NSURLConnection *)connection didSendBodyData:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite {
    float progress = (float)totalBytesWritten/(float)totalBytesExpectedToWrite;
    [self performSelectorOnMainThread:@selector(postProgressNotification:) withObject:[NSNotification notificationWithName:@"PublishProgressUpdated" object:[NSNumber numberWithFloat:progress]] waitUntilDone:NO];
}

- (void) postProgressNotification:(NSNotification *) notification {
    [[NSNotificationCenter defaultCenter] postNotification:notification];
}

@end
