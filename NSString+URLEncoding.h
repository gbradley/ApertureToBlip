//
// NSString+URLEncoding.h
//
// Created by Graham Bradley on 14/09/2012.
//
// Just a tiny category to allow for easy string URL encoding.

#import <Foundation/Foundation.h>

@interface NSString (URLEncoding)

+ (NSString *) URLEncodedStringFromString:(NSString *) str;

@end