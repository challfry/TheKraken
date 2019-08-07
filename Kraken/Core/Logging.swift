//
//  Logging.swift
//  Kraken
//
//  Created by Chall Fry on 6/27/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

/*	A Short Dissertation on Why I Don't Just Use OSLog
	tl;dr it's really awful.
	Almost no swift support. You can't really wrap it in your own logging, which means you can't multiplex with it.
	Although os_log records file and line numbers, you can't see them in Console, two years after os_log shipped.
	You can only see them in the CLI; near useless for interactive debugging. Only static strings is too restrictive
	for use in interactive debugging. Xcode itself has almost no support for os_logs' features.
	
	Yes I know what they were trying to do. I mostly use logging for interactive debugging and need a system that
	is excellent at that, and want a system that also works okay for post analysis of user crashes. Not the other way around. 

	With better tooling support, and a better API in Swift, it could be really great. All the stuff in the middle is
	well-designed. 
*/


import UIKit
import os

// Logging front ends create one of these objects for each log message  and send it to the LogMessageMultiplexer.
struct LogMessageData {

	// Logging 'front ends' should fill in these fields 
	let messageClosure: () -> String
	let objectsClosure: (() -> [String : Any]?)?
	let level: OSLogType
	let logObject: OSLog?
	let file: StaticString
	let function: String
	let line: UInt
	
	lazy var message: String = messageClosure()
	lazy var objects: [String : Any]? = objectsClosure?() 

	init(messageClosure: @escaping () -> String, objectsClosure: (()-> [String: Any]?)?, 
			level: OSLogType, logObject: OSLog?, file: StaticString, function: String,  line: UInt)
	{
		self.messageClosure = messageClosure
		self.objectsClosure = objectsClosure
		self.level = level
		self.logObject = logObject
		self.file = file
		self.function = function
		self.line = line
	}
	
	lazy var shortMessage: String = buildShortMessage()
	mutating private func buildShortMessage() -> String {
		var shortMessage = ""
		if let objects = objects {
			objects.sorted(by: { $0.key < $1.key }).forEach { key, value in 
				shortMessage.append("\(key) = \(String(reflecting:value)) | ")
			}
		}
		
		if shortMessage.count == 0 {
			shortMessage = message
		}
		else if message.count > 0 {
			if shortMessage.count + message.count < 120 {
				shortMessage = "\(message) | \(shortMessage)"
			}
			else {
				shortMessage = "\(message)\n    \(shortMessage)"
			}
		}
		return shortMessage
	}
	
	lazy var fullMessage: String = buildFullMessage()
	mutating private func buildFullMessage() -> String {
		var fullMessage = "\(message) in: \(function) at \(file):\(line)"
		if let objects = objects {
			fullMessage.append("\n    ")
			objects.forEach { key, value in 
				fullMessage.append("\(key) : \(value) | ")
			}
		}
		return fullMessage
	}
}

struct LogMessageMultiplexer {

	// Modify these lines to change where log messages go.
	static let sendViaPrint = true
	static let sendViaNSLog = false
	static let sendViaOSLog = false
	
	// Once the logging front-end builds a LogMessageData, it can send it here
	// This whole thing could be a bunch of protocols and delegate objects, but: why?
	static func send(_ msgData: inout LogMessageData) {
		if sendViaPrint {
			print(msgData.shortMessage)
		}
		if sendViaNSLog {
			NSLog(msgData.fullMessage)
		}
		if sendViaOSLog {
			// Why not just us os_log directly? See notes, above.
			os_log("%{public}@", log: msgData.logObject ?? .default, type: msgData.level, msgData.message)
		}
	}
	
}

protocol LoggingProtocol {
	static var logObject: OSLog { get }
	static var isEnabled: Bool { get set}
	var instanceEnabled: Bool { get set }

	@inlinable static func d(_ message:  @escaping @autoclosure () -> String, 
			_ objects: @escaping @autoclosure () -> [String:Any]?,
			file: StaticString, function: String, line: UInt)
	@inlinable static func debug(_ message:  @escaping @autoclosure () -> String, 
			_ objects: @escaping @autoclosure () -> [String:Any]?,
			file: StaticString, function: String, line: UInt)
	@inlinable static func error(_ message:  @escaping @autoclosure () -> String, 
			_ objects: @escaping @autoclosure () -> [String:Any]?,
			file: StaticString, function: String, line: UInt)
	@inlinable static func info(_ message:  @escaping @autoclosure () -> String, 
			_ objects: @escaping @autoclosure () -> [String:Any]?,
			file: StaticString, function: String, line: UInt)
	@inlinable static func fault(_ message:  @escaping @autoclosure () -> String, 
			_ objects: @escaping @autoclosure () -> [String:Any]?,
			file: StaticString, function: String, line: UInt)

	@inlinable static func assert(_ condition: @autoclosure () -> Bool, 
			_ message: @escaping @autoclosure () -> String,
			_ objects: @escaping @autoclosure () -> [String:Any]?,
			file: StaticString, function: String, line: UInt)
}

extension LoggingProtocol {
	@inlinable static public func d(_ message: @escaping @autoclosure () -> String,
			_ objects: @escaping @autoclosure () -> [String:Any]? = nil,
			file: StaticString = #file, function: String = #function, line: UInt = #line) {
		if isEnabled {
			var msgData = LogMessageData(messageClosure: message, objectsClosure: objects, 
					level: .default, logObject: logObject, file: file, function: function, line: line)
			LogMessageMultiplexer.send(&msgData)
		}
	}
	
	@inlinable static public func debug(_ message: @escaping @autoclosure () -> String,
			_ objects: @escaping @autoclosure () -> [String:Any]? = nil,
			file: StaticString = #file, function: String = #function, line: UInt = #line) {
		if isEnabled {
			var msgData = LogMessageData(messageClosure: message, objectsClosure: objects, 
					level: .debug, logObject: logObject, file: file, function: function, line: line)
			LogMessageMultiplexer.send(&msgData)
		}
	}
	
	@inlinable static public func error(_ message: @escaping @autoclosure () -> String,
			_ objects: @escaping @autoclosure () -> [String:Any]? = nil,
			file: StaticString = #file, function: String = #function, line: UInt = #line) {
		if isEnabled {
			var msgData = LogMessageData(messageClosure: message, objectsClosure: objects, 
					level: .error, logObject: logObject, file: file, function: function, line: line)
			LogMessageMultiplexer.send(&msgData)
		}
	}
	
	@inlinable static public func info(_ message: @escaping @autoclosure () -> String,
			_ objects: @escaping @autoclosure () -> [String:Any]? = nil,
			file: StaticString = #file, function: String = #function, line: UInt = #line) {
		if isEnabled {
			var msgData = LogMessageData(messageClosure: message, objectsClosure: objects, 
					level: .info, logObject: logObject, file: file, function: function, line: line)
			LogMessageMultiplexer.send(&msgData)
		}
	}
	
	@inlinable static public func fault(_ message: @escaping @autoclosure () -> String,
			_ objects: @escaping @autoclosure () -> [String:Any]? = nil,
			file: StaticString = #file, function: String = #function, line: UInt = #line) {
		if isEnabled {
			var msgData = LogMessageData(messageClosure: message, objectsClosure: objects, 
					level: .fault, logObject: logObject, file: file, function: function, line: line)
			LogMessageMultiplexer.send(&msgData)
		}
	}
	
	@inlinable static public func assert(_ condition: @autoclosure () -> Bool, 
			_ message: @escaping @autoclosure () -> String,
			_ objects: @escaping @autoclosure () -> [String:Any]? = nil,
			file: StaticString = #file, function: String = #function, line: UInt = #line) {
		#if DEBUG
		if isEnabled && !condition() {
			var msgData = LogMessageData(messageClosure: message, objectsClosure: objects, 
					level: .fault, logObject: logObject, file: file, function: function, line: line)
			LogMessageMultiplexer.send(&msgData)
			
			// Optionally, we could also stop in the debugger here.
			// assert(true, message(), file: file, line: line)
		}
		#endif
	}
	
	@inlinable public func d(_ message: @escaping @autoclosure () -> String,
			_ objects: @escaping @autoclosure () -> [String:Any]? = nil,
			file: StaticString = #file, function: String = #function, line: UInt = #line) {
		if instanceEnabled {
			var msgData = LogMessageData(messageClosure: message, objectsClosure: objects, 
					level: .debug, logObject: Self.logObject, file: file, function: function, line: line)
			LogMessageMultiplexer.send(&msgData)
		}
	}
	
	@inlinable public func debug(_ message: @escaping @autoclosure () -> String,
			_ objects: @escaping @autoclosure () -> [String:Any]? = nil,
			file: StaticString = #file, function: String = #function, line: UInt = #line) {
		if instanceEnabled {
			var msgData = LogMessageData(messageClosure: message, objectsClosure: objects, 
					level: .debug, logObject: Self.logObject, file: file, function: function, line: line)
			LogMessageMultiplexer.send(&msgData)
		}
	}
	
	@inlinable public func error(_ message: @escaping @autoclosure () -> String,
			_ objects: @escaping @autoclosure () -> [String:Any]? = nil,
			file: StaticString = #file, function: String = #function, line: UInt = #line) {
		if instanceEnabled {
			var msgData = LogMessageData(messageClosure: message, objectsClosure: objects, 
					level: .debug, logObject: Self.logObject, file: file, function: function, line: line)
			LogMessageMultiplexer.send(&msgData)
		}
	}
	
	@inlinable public func info(_ message: @escaping @autoclosure () -> String,
			_ objects: @escaping @autoclosure () -> [String:Any]? = nil,
			file: StaticString = #file, function: String = #function, line: UInt = #line) {
		if instanceEnabled {
			var msgData = LogMessageData(messageClosure: message, objectsClosure: objects, 
					level: .debug, logObject: Self.logObject, file: file, function: function, line: line)
			LogMessageMultiplexer.send(&msgData)
		}
	}
	
	@inlinable public func fault(_ message: @escaping @autoclosure () -> String,
			_ objects: @escaping @autoclosure () -> [String:Any]? = nil,
			file: StaticString = #file, function: String = #function, line: UInt = #line) {
		if instanceEnabled {
			var msgData = LogMessageData(messageClosure: message, objectsClosure: objects, 
					level: .debug, logObject: Self.logObject, file: file, function: function, line: line)
			LogMessageMultiplexer.send(&msgData)
		}
	}
	
}

// MARK: - Logging Objects
//	To use:
//		NetworkLog.d(message)			// Sends a debug message in the Network category

struct CollectionViewLog: LoggingProtocol {
	var instanceEnabled: Bool
		
	static var logObject = OSLog.init(subsystem: "com.challfry.Kraken", category: "CollectionView")
	static var isEnabled = true
}

struct NetworkLog: LoggingProtocol {
	var instanceEnabled: Bool
	
	static var logObject = OSLog.init(subsystem: "com.challfry.Kraken", category: "Network")
	static var isEnabled = true
}

struct CoreDataLog: LoggingProtocol {
	var instanceEnabled: Bool
	
	static var logObject = OSLog.init(subsystem: "com.challfry.Kraken", category: "CoreData")
	static var isEnabled = true
}

struct KeychainLog: LoggingProtocol {
	var instanceEnabled: Bool
	
	static var logObject = OSLog.init(subsystem: "com.challfry.Kraken", category: "Keychain")
	static var isEnabled = true
}

struct ImageLog: LoggingProtocol {
	var instanceEnabled: Bool
	
	static var logObject = OSLog.init(subsystem: "com.challfry.Kraken", category: "Image Manager")
	static var isEnabled = true
}

struct CameraLog: LoggingProtocol {
	var instanceEnabled: Bool
	
	static var logObject = OSLog.init(subsystem: "com.challfry.Kraken", category: "Camera")
	static var isEnabled = true
}

func makeAddrString(_ object: AnyObject) -> String {
	return "\(Unmanaged.passUnretained(object).toOpaque())"
}
