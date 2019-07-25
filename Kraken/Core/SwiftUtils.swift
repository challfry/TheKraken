//
//  SwiftUtils.swift
//  Kraken
//
//  Created by Chall Fry on 7/24/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

func weakify <T: AnyObject>(_ owner: T, _ f: @escaping (T)->()->()) -> () -> () {
    return { [weak owner] in
        if let owner = owner {
            f(owner)()
        }
    }
}

func weakify <T: AnyObject, R>(_ owner: T, _ f: @escaping (T)->()->(R)) -> () -> R? {
    return { [weak owner] in
        if let owner = owner {
            return f(owner)()
        }
        return nil
    }
}

func weakify <T: AnyObject, Param>(_ owner: T, _ f: @escaping (T)->(Param)->()) -> (Param) -> () {
    return { [weak owner] (param: Param) in
        if let owner = owner {
            f(owner)(param)
        }
    }
}

