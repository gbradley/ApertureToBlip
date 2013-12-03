//
//  DataController.h
//  ApertureToBlip
//
//  Created by Graham Bradley on 24/04/2010.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface DataController : NSObject {
	
	NSString *auth_username;
	NSString *auth_token;
    BOOL visitJournalAfterExport;
	
}

@property (copy, nonatomic) NSString *auth_username;
@property (copy, nonatomic) NSString *auth_token;
@property BOOL visitJournalAfterExport;

- (void) saveData;

@end
