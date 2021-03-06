/***********************************************************************
 ** Etresoft
 ** John Daniel
 ** Copyright (c) 2014-2017. All rights reserved.
 **********************************************************************/

#import "NetworkUsageCollector.h"
#import "NSMutableAttributedString+Etresoft.h"
#import "ByteCountFormatter.h"
#import "SubProcess.h"
#import "Utilities.h"
#import "Model.h"
#import "NumberFormatter.h"

// Collect information about network usage.
@implementation NetworkUsageCollector

@synthesize processesByPID = myProcessesByPID;

// Constructor.
- (id) init
  {
  self = [super initWithName: @"network"];
  
  if(self != nil)
    {
    }
    
  return self;
  }

// Destructor.
- (void) dealloc
  {
  [myProcessesByPID release];
  
  [super dealloc];
  }

// Perform the collection.
- (void) performCollect
  {
  int version = [[Model model] majorOSVersion];

  if(version >= kSierra)
    {
    // Collect the average memory usage usage for all processes (5 times).
    NSArray * processes = [self collectNetwork];
    
    self.processesByPID = [super collectProcesses];
    
    // Print the top processes.
    [self printTopProcesses: processes];
    }
  }

// Collect processes' network usage.
- (NSArray *) collectNetwork
  {
  NSArray * args =
    @[
      @"-Px",
      @"-k",
      @"interface,state,rx_ooo,rx_dupe,re-tx,rtt_avg,rcvsize,tx_win,tc_class,tc_mgt,cc_algo,P,C,R,W",
      @"-l",
      @"1",
      @"-t",
      @"external"
    ];
  
  NSMutableArray * processes = [NSMutableArray array];
    
  SubProcess * subProcess = [[SubProcess alloc] init];
  
  if([subProcess execute: @"/usr/bin/nettop" arguments: args])
    {
    NSArray * lines = [Utilities formatLines: subProcess.standardOutput];
    
    for(NSString * line in lines)
      {
      if([line hasPrefix: @"STAT"])
        continue;

      NSDictionary * process = [self parseNetTop: line];

      if(!process)
        continue;
        
      [processes addObject: process];
      }
    }
    
  [subProcess release];
  
  [self sortProcesses: processes];
    
  return processes;
  }

// Sort the processes.
- (void) sortProcesses: (NSMutableArray *) processes
  {
  [processes
    sortUsingComparator:
      ^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2)
      {
      NSDictionary * process1 = obj1;
      NSDictionary * process2 = obj2;
      
      NSNumber * bytesIn1 = [process1 objectForKey: @"bytesIn"];
      NSNumber * bytesOut1 = [process1 objectForKey: @"bytesOut"];
      
      NSNumber * bytesIn2 = [process2 objectForKey: @"bytesIn"];
      NSNumber * bytesOut2 = [process2 objectForKey: @"bytesOut"];
      
      unsigned long long total1 =
        [bytesIn1 unsignedLongLongValue] +
          [bytesOut1 unsignedLongLongValue];

      unsigned long long total2 =
        [bytesIn2 unsignedLongLongValue] +
          [bytesOut2 unsignedLongLongValue];
        
      if(total1 > total2)
        return NSOrderedAscending;
      else if(total1 < total2)
        return NSOrderedDescending;
        
      return NSOrderedSame;
      }];
  }

// Parse a single process.
- (NSDictionary *) parseNetTop: (NSString *) line
  {
  NSScanner * scanner = [NSScanner scannerWithString: line];
  
  NSString * time = NULL;
  
  BOOL success =
    [scanner
      scanUpToCharactersFromSet: [NSCharacterSet whitespaceCharacterSet]
      intoString: & time];
    
  if(!success)
    return nil;
    
  // Skip first line.
  if([time isEqualToString: @"time"])
    return nil;
    
  NSString * process = NULL;
  
  success =
    [scanner
      scanUpToCharactersFromSet: [NSCharacterSet whitespaceCharacterSet]
      intoString: & process];
    
  if(!success)
    return nil;
    
  NSRange PIDRange =
    [process rangeOfString: @"." options: NSBackwardsSearch];
  
  NSNumber * pid = [NSNumber numberWithInteger: 0];
  
  if(PIDRange.location != NSNotFound)
    {
    if(PIDRange.location < [process length])
      pid =
        [[NumberFormatter sharedNumberFormatter]
          convertFromString:
            [process substringFromIndex: PIDRange.location + 1]];
    
    process = [process substringToIndex: PIDRange.location];
    }
    
  long long bytesIn;
  
  success = [scanner scanLongLong: & bytesIn];

  if(!success)
    return nil;
    
  long long bytesOut;
  
  success = [scanner scanLongLong: & bytesOut];
  
  if(!success)
    return nil;
    
  return
    [NSDictionary
      dictionaryWithObjectsAndKeys:
        process, @"process",
        pid, @"pid",
        [NSNumber numberWithLongLong: bytesIn], @"bytesIn",
        [NSNumber numberWithLongLong: bytesOut], @"bytesOut",
        nil];
  }

// Print top processes by memory.
- (void) printTopProcesses: (NSArray *) processes
  {
  [self.result appendAttributedString: [self buildTitle]];
  
  [self.result
    appendString:
      [NSString
        stringWithFormat:
          @"    %@\t%@\t%@\n",
          NSLocalizedString(@"Input     ", NULL),
          NSLocalizedString(@"Output    ", NULL),
          NSLocalizedString(@"Process name", NULL)]
    attributes:
      @{ NSFontAttributeName : [[Utilities shared] boldFont] }];

  NSUInteger count = 0;
  
  ByteCountFormatter * formatter = [[ByteCountFormatter alloc] init];

  formatter.k1000 = 1024.0;
  
  for(NSDictionary * process in processes)
    {
    [self printTopProcess: process formatter: formatter];
    
    ++count;
          
    if(count >= 5)
      break;
    }

  [self.result appendCR];
  
  [formatter release];
  }

// Print a top process.
- (void) printTopProcess: (NSDictionary *) process
  formatter: (ByteCountFormatter *) formatter
  {
  // Cross-reference the process ID to get a decent process name using
  // "ps" results that are better than names from "nettop".
  NSString * processName = nil;
  
  NSNumber * pid = [process objectForKey: @"pid"];
  
  NSDictionary * processByPID = [self.processesByPID objectForKey: pid];
  
  if(processByPID != nil)
    processName = [processByPID objectForKey: @"command"];
    
  if(processName == nil)
    processName = [process objectForKey: @"process"];
  
  if([processName length] == 0)
    processName = NSLocalizedString(@"Unknown", NULL);
    
  if([processName hasPrefix: @"EtreCheck"])
    return;

  double bytesIn = [[process objectForKey: @"bytesIn"] doubleValue];
  double bytesOut = [[process objectForKey: @"bytesOut"] doubleValue];

  NSString * bytesInString =
    [formatter stringFromByteCount: (unsigned long long)bytesIn];

  NSString * bytesOutString =
    [formatter stringFromByteCount: (unsigned long long)bytesOut];
  
  NSString * printBytesInString =
    [bytesInString
      stringByPaddingToLength: 10 withString: @" " startingAtIndex: 0];

  NSString * printBytesOutString =
    [bytesOutString
      stringByPaddingToLength: 10 withString: @" " startingAtIndex: 0];

  [self.result
    appendString:
      [NSString
        stringWithFormat:
          @"    %@\t%@\t%@\n",
          printBytesInString,
          printBytesOutString,
          processName]];
  }

@end
