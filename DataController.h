//
//  DataController.h
//  ApertureToBlip
//

#import <Cocoa/Cocoa.h>


@interface DataController : NSObject {
	
	NSString *displayName;
	NSString *userToken;
    NSString *userSecret;
    BOOL visitJournalAfterExport;
	
}

@property (copy, nonatomic) NSString *displayName;
@property (copy, nonatomic) NSString *userToken;
@property (copy, nonatomic) NSString *userSecret;
@property BOOL visitJournalAfterExport;

- (void) saveData;

@end
