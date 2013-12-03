//
//  DataController.m
//  ApertureToBlip
//
//  Created by Graham Bradley on 24/04/2010.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "DataController.h"


@implementation DataController

@synthesize auth_username, auth_token, visitJournalAfterExport;

- (id) init {
	
	NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    if (![prefs boolForKey:@"initialised"]){
        
        [prefs setObject:@"-1" forKey:@"auth_username"];
        [prefs setObject:@"-1" forKey:@"auth_token"];
        [prefs setBool:YES forKey:@"visitJournalAfterExport"];
        [prefs setBool:YES forKey:@"initialised"];
        [prefs synchronize];
        
    }
    
    NSLog(@"%@", [[NSUserDefaults standardUserDefaults] dictionaryRepresentation]);
    
    self.auth_token = [prefs objectForKey:@"auth_token"];
    self.auth_username = [prefs objectForKey:@"auth_username"];
    self.visitJournalAfterExport = [prefs boolForKey:@"visitJournalAfterExport"];
	
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
	
	return self;
	
}

- (void) saveData {
    
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    [prefs setObject:self.auth_username forKey:@"auth_username"];
    [prefs setObject:self.auth_token forKey:@"auth_token"];
    [prefs setBool:self.visitJournalAfterExport forKey:@"visitJournalAfterExport"];
    [prefs synchronize];
}

@end
