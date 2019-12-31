//
//  ObjCUtils.m
//  Kraken
//
//  Created by Chall Fry on 12/30/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

#import <Foundation/Foundation.h>

NSError *objcExceptionWrapper(void(^tryBlock)(void))
{
    @try {
        tryBlock();
    }
    @catch (NSException *exception) {
        NSError *error = [NSError errorWithDomain:@"ConvertedObjCException" code:0 userInfo:nil];
        return error;
    }
	
	return nil;
}
