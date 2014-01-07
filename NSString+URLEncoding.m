//
//  NSString+URLEncoding.m
//
//  Created by Graham Bradley on 14/09/2012.
//
//

#import "NSString+URLEncoding.h"

@implementation NSString (URLEncoding)

+ (NSString *) URLEncodedStringFromString:(NSString *) str {
    
    CFStringRef strRef = (__bridge  CFStringRef) str;
    CFStringRef urlRef = CFURLCreateStringByAddingPercentEscapes(NULL, strRef, NULL, (CFStringRef)@"!*'();:@&=+$,/?%#[]", kCFStringEncodingUTF8);
    NSString *encodedStr = [NSString stringWithString:(__bridge NSString *)urlRef];
    CFRelease(urlRef);
    return encodedStr;
}

@end
