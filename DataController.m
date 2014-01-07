//
//  DataController.m
//  ApertureToBlip
//

#import "DataController.h"


@implementation DataController

@synthesize displayName, userToken, userSecret, visitJournalAfterExport;

- (id) init {
	
	NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    if ([prefs integerForKey:@"version"] == 0) {
        [prefs setObject:@"" forKey:@"displayName"];
        [prefs setObject:@"" forKey:@"userToken"];
        [prefs setObject:@"" forKey:@"userSecret"];
        [prefs setBool:YES forKey:@"visitJournalAfterExport"];
        [prefs setInteger:1 forKey:@"version"];
        [prefs synchronize];
    }
    
    self.displayName = [prefs objectForKey:@"displayName"];
    self.userToken = [prefs objectForKey:@"userToken"];
    self.userSecret = [prefs objectForKey:@"userSecret"];
    self.visitJournalAfterExport = [prefs boolForKey:@"visitJournalAfterExport"];
	
    return self;
}

- (id) copyWithZone:(NSZone *)zone {
	return self;
}

- (void) saveData {
    
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    [prefs setObject:self.displayName forKey:@"displayName"];
    [prefs setObject:self.userToken forKey:@"userToken"];
    [prefs setObject:self.userSecret forKey:@"userSecret"];
    [prefs setBool:self.visitJournalAfterExport forKey:@"visitJournalAfterExport"];
    [prefs synchronize];

}

@end
