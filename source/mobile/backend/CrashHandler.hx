package mobile.backend;

import openfl.events.UncaughtErrorEvent;
import openfl.events.ErrorEvent;
import openfl.errors.Error;
import haxe.Date;
import haxe.DateTools;
import haxe.CallStack;

#if sys
import sys.FileSystem;
import sys.io.File;
#end
#if js
import js.Browser;
#end
#if java
import java.lang.Thread;
#end
#if cs
import cs.system.AppDomain;
#end

using StringTools;

/**
 * Universal Crash Handler.
 * Handles uncaught errors, critical native crashes, and async rejections across all platforms.
 * @author YoshiCrafter29, Ne_Eo, MAJigsaw77, Homura Akemi (HomuHomu833), Upgraded
 */
class CrashHandler
{
	private static var isHandlingCrash:Bool = false;
	private static var logBuffer:Array<String> = [];
	private static var MAX_LOG_BUFFER:Int = 50;

	public static function init():Void
	{
		#if (openfl || flash)
		try {
			openfl.Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onUncaughtError);
		} catch(e:Dynamic) {
		}
		#end

		#if cpp
		try {
			cpp.vm.Thread.setCriticalErrorHandler(onError);
		} catch(e:Dynamic) {
			untyped __global__.__hxcpp_set_critical_error_handler(onError);
		}
		#end

		#if hl
		hl.Api.setErrorHandler(onError);
		#end

		#if js
		js.Browser.window.onerror = function(msg:Dynamic, url:String, line:Int, col:Int, error:Dynamic):Bool {
			onError("JS Global Error: " + msg + " at " + url + ":" + line + ":" + col);
			return true;
		};
		js.Browser.window.addEventListener("unhandledrejection", function(e:js.html.PromiseRejectionEvent):Void {
			onError("JS Unhandled Promise Rejection: " + Std.string(e.reason));
		});
		#end

		#if java
		try {
			java.lang.Thread.setDefaultUncaughtExceptionHandler(new java.lang.Thread.UncaughtExceptionHandler() {
				public function uncaughtException(t:java.lang.Thread, e:java.lang.Throwable):Void {
					var sw = new java.io.StringWriter();
					e.printStackTrace(new java.io.PrintWriter(sw));
					onError("Java Uncaught Exception: " + e.toString() + "\n" + sw.toString());
				}
			});
		} catch(e:Dynamic) {}
		#end

		#if cs
		try {
			cs.system.AppDomain.currentDomain.add_UnhandledException(function(sender:cs.system.Object, e:cs.system.UnhandledExceptionEventArgs):Void {
				onError("C# Unhandled Exception: " + e.ExceptionObject.toString());
			});
		} catch(e:Dynamic) {}
		#end
	}

	/**
	 * Log a message to the crash handler's internal buffer.
	 * If a crash occurs, the last 50 log entries will be appended to the crash report.
	 * Highly recommended for tracking down the sequence of events leading to a crash.
	 * 
	 * @param message The message to log.
	 * @param type The type of log (e.g., "INFO", "WARN", "ERROR"). Defaults to "INFO".
	 */
	public static function log(message:Dynamic, ?type:String = "INFO"):Void
	{
		var timestamp = DateTools.format(Date.now(), "%H:%M:%S");
		var entry = '[$timestamp] [$type] ${Std.string(message)}';
		
		logBuffer.push(entry);
		if (logBuffer.length > MAX_LOG_BUFFER) {
			logBuffer.shift();
		}
		
		#if sys
		Sys.println(entry);
		#elseif js
		js.Browser.console.log(entry);
		#else
		trace(entry);
		#end
	}

	private static function onUncaughtError(e:UncaughtErrorEvent):Void
	{
		if (isHandlingCrash) return;
		isHandlingCrash = true;

		e.preventDefault();
		e.stopPropagation();
		e.stopImmediatePropagation();

		var err = e.error;
		var m:String = "Unknown Error";
		
		if (err != null) {
			if (Std.isOfType(err, Error)) {
				m = cast(err, Error).message;
			} else if (Std.isOfType(err, ErrorEvent)) {
				m = cast(err, ErrorEvent).text;
			} else if (Std.isOfType(err, haxe.Exception)) {
				m = cast(err, haxe.Exception).message;
			} else {
				m = Std.string(err);
			}
		}

		var stackLabel = formatStackTrace(haxe.CallStack.exceptionStack());
		var fullMessage = "ERROR: " + m + "\n\n[Stack Trace]\n" + stackLabel;
		
		if (logBuffer.length > 0) {
			fullMessage += "\n\n[Recent Logs / Warnings]\n" + logBuffer.join("\n");
		}

		#if sys
		saveErrorMessage(fullMessage);
		#end

		safeShutdown(fullMessage);
	}

	#if (cpp || hl || java || cs || js)
	private static function onError(message:Dynamic):Void
	{
		if (isHandlingCrash) return;
		isHandlingCrash = true;

		var m:String = message != null ? Std.string(message) : "Unknown Critical Error";
		var stack = haxe.CallStack.exceptionStack(true);
		var stackLabel = formatStackTrace(stack);
		
		var fullMessage = "CRITICAL ERROR: " + m + "\n\n[Stack Trace]\n" + stackLabel;
		
		if (logBuffer.length > 0) {
			fullMessage += "\n\n[Recent Logs / Warnings]\n" + logBuffer.join("\n");
		}

		#if sys
		saveErrorMessage(fullMessage);
		#end

		safeShutdown(fullMessage);
	}
	#end

	private static function formatStackTrace(stack:haxe.CallStack):String
	{
		var stackLabelArr:Array<String> = [];
		for (item in stack) {
			switch (item) {
				case CFunction:
					stackLabelArr.push("  [C Function]");
				case Module(m):
					stackLabelArr.push("  Module: " + m);
				case FilePos(parent, file, line, col):
					var parentStr = switch (parent) {
						case Method(cla, func): cla + "." + func;
						case null: "Unknown";
						case _: Std.string(parent);
					}
					stackLabelArr.push("  " + file + ":" + line + " (" + parentStr + ")");
				case LocalFunction(v):
					stackLabelArr.push("  Local Function: " + v);
				case Method(cl, m):
					stackLabelArr.push("  " + cl + "." + m);
			}
		}
		
		var cleanStack = stackLabelArr.join("\n");
		var rawStack = haxe.CallStack.toString(stack);
		
		if (cleanStack == "") {
			return rawStack;
		} else {
			return cleanStack + "\n\n[Raw Stack Dump]\n" + rawStack;
		}
	}

	private static function safeShutdown(fullMessage:String):Void
	{
		try {
			CoolUtil.showPopUp(fullMessage, "Critical Error!");
		} catch(e:Dynamic) {
			#if js
			js.Browser.window.alert("Critical Error: Check console or logs/ folder.");
			#elseif sys
			Sys.println("--- CRITICAL ERROR ---\n" + fullMessage);
			#end
		}

		#if DISCORD_ALLOWED 
		try {
			DiscordClient.shutdown();
		} catch(e:Dynamic) {}
		#end

		#if sys
		try {
			lime.system.System.exit(1);
		} catch(e:Dynamic) {}
		#end
	}

	#if sys
	private static function saveErrorMessage(message:String):Void
	{
		try 
		{
			var logDir = "";
			try {
				logDir = lime.system.System.applicationStorageDirectory;
			} catch(e:Dynamic) {}

			if (logDir == null || logDir == "") {
				#if android
				try {
					logDir = StorageUtil.getExternalStorageDirectory() + "/";
				} catch(e:Dynamic) {
					logDir = "./";
				}
				#else
				logDir = Sys.getCwd();
				if (logDir == null) logDir = "./";
				#end
			}

			if (!logDir.endsWith("/") && !logDir.endsWith("\\")) {
				logDir += "/";
			}
			logDir += "logs/";

			if (!FileSystem.exists(logDir)) {
				FileSystem.createDirectory(logDir);
			}

			var dateStr = DateTools.format(Date.now(), "%Y-%m-%d_%H-%M-%S");
			var filePath = logDir + "crash_" + dateStr + ".txt";
			
			File.saveContent(filePath, message);
			File.saveContent(logDir + "latest_crash.txt", message);
		}
		catch (e:Dynamic) 
		{
			#if sys
			Sys.println("Failed to save crash log: " + e);
			#end
		}
	}
	#end
}
