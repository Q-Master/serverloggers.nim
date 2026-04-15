import std/[strutils, logging, times]
import ./[tagger, util]


type
  LoggerFormatters* {.size: sizeof(uint8), pure.} = enum
    LF_NAME         ## Name of the logger (logging channel)
    LF_LEVEL_NO     ## Numeric logging level for the message (DEBUG, INFO, WARNING, ERROR, CRITICAL)
    LF_LEVEL_NAME   ## Text logging level for the message ("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL")
    LF_FILE_NAME    ## Filename portion of pathname
    LF_LINE_NO      ## Source line number where the logging call was issued (if available)
    LF_ASCTIME      ## Textual time when the log record was created by default YYYY-mm-dd HH:MM:SS
    LF_MSECS        ## Millisecond portion of the creation time rounded to 3 leading digits
    LF_THREAD_ID    ## Thread ID (if available)
    LF_PROCESS_ID   ## Process ID (if available)
    LF_PROCESS_NAME ## Process Name (if available)
    LF_TAGS         ## Tags attached to the logger in simple JSON notation
    LF_MESSAGE      ## The message of a log record
    LF_HOSTNAME     ## The current host name

  LoggerFormatter* = ref object
    fmt: seq[uint8]


const YEAR_MONTH_DAY = "yyyy-MM-dd"
const HOUR_MINUTE_SECOND = "hh:mm:ss"
const DATE_FORMAT = YEAR_MONTH_DAY & " " & HOUR_MINUTE_SECOND
const DATE_FORMAT_LENGHT = DATE_FORMAT.len
const MSECS_LEN = 3


let namesTable: array[logging.Level, char] = [
  'D', 'D', 'I', 'N', 'W', 'E', 'F', 'D'
]


func len(n: int): int {.inline.} =
  if n > 999999:
    result = 7
  elif n > 99999:
    result = 6
  elif n > 9999:
    result = 5
  elif n > 999:
    result = 4
  elif n > 99:
    result = 3
  elif n > 9:
    result = 2
  else:
    result = 1


proc newFormatter*(fmt: string): LoggerFormatter =
  result.new
  result.fmt = @[]
  var token: bool = false
  var tokenStr: string
  var i = 0
  while i < fmt.len:
    if token:
      if fmt[i] in Letters:
        tokenStr.add(fmt[i])
      elif fmt[i] == ')':
        token = false
        case tokenStr.toLowerAscii
        of "name": result.fmt.add(LF_NAME.uint8)
        of "levelno": result.fmt.add(LF_LEVEL_NO.uint8)
        of "levelname": result.fmt.add(LF_LEVEL_NAME.uint8)
        of "filename": result.fmt.add(LF_FILE_NAME.uint8)
        of "lineno": result.fmt.add(LF_LINE_NO.uint8)
        of "asctime": result.fmt.add(LF_ASCTIME.uint8)
        of "msecs": result.fmt.add(LF_MSECS.uint8)
        of "thread": result.fmt.add(LF_THREAD_ID.uint8)
        of "process": result.fmt.add(LF_PROCESS_ID.uint8)
        of "pname": result.fmt.add(LF_PROCESS_NAME.uint8)
        of "tags": result.fmt.add(LF_TAGS.uint8)
        of "message": result.fmt.add(LF_MESSAGE.uint8)
        of "node": result.fmt.add(LF_HOSTNAME.uint8)
      else:
        token = false
        result.fmt.add('%'.uint8)
        result.fmt.add('('.uint8)
        for td in tokenStr:
          result.fmt.add(td.uint8)
    else:
      if fmt[i] == '%' and i+1 < fmt.len and fmt[i+1] == '(':
        token = true
        tokenStr = ""
        i.inc
      else:
        result.fmt.add(fmt[i].uint8)
    i.inc


proc buildReal(
  self: LoggerFormatter, tagger: LoggerTagger,
  level: Level,
  name, hostName, filename, lineno: openArray[char],
  processId: int,
  processName: openArray[char],
  threadId: int,
  message: openArray[char]): string =
  var strlen = 0
  for code in self.fmt:
    case code
    of LF_NAME.uint8:
      strlen.inc(name.len)
    of LF_LEVEL_NO.uint8:
      strlen.inc
    of LF_LEVEL_NAME.uint8:
      strlen.inc
    of LF_FILE_NAME.uint8:
      strlen.inc(filename.len)
    of LF_LINE_NO.uint8:
      strlen.inc(lineno.len)
    of LF_ASCTIME.uint8:
      strlen.inc(DATE_FORMAT_LENGHT)
    of LF_MSECS.uint8:
      strlen.inc(MSECS_LEN)
    of LF_THREAD_ID.uint8:
      when useThreads:
        if threadId >= 0:
          strlen.inc(threadId.len)
        else:
          # thread ID is -1
          strlen.inc(2)
    of LF_PROCESS_ID.uint8:
      if processId >= 0:
        strlen.inc(processId.len())
      else:
        # process ID is -1
        strlen.inc(2)
    of LF_PROCESS_NAME.uint8:
      strlen.inc(processName.len)
    of LF_TAGS.uint8:
      strlen.inc(tagger.len)
    of LF_MESSAGE.uint8:
      strlen.inc(message.len)
    of LF_HOSTNAME.uint8:
      strlen.inc(hostName.len)
    else:
      strlen.inc
  result.setLen(strlen)
  var destUnchecked = cast[ptr UncheckedArray[char]](result[0].addr)
  var at = 0
  template add(ds: ptr UncheckedArray[char], c: char) =
    ds[at] = c
    at.inc
  template add(ds: ptr UncheckedArray[char], s: openArray[char]) =
    for c in s:
      ds.add(c)
  let ts = now()
  for code in self.fmt:
    case code
    of LF_NAME.uint8:
      for n in name:
        destUnchecked.add(n)
    of LF_LEVEL_NO.uint8:
      destUnchecked.add(('0'.uint8+level.uint8).char)
    of LF_LEVEL_NAME.uint8:
      destUnchecked.add(namesTable[level])
    of LF_FILE_NAME.uint8:
      for n in filename:
        destUnchecked.add(n)
    of LF_LINE_NO.uint8:
      destUnchecked.add(lineno)
    of LF_ASCTIME.uint8:
      destUnchecked.add(ts.format(DATE_FORMAT))
    of LF_MSECS.uint8:
      let ms = $convert(Nanoseconds, Milliseconds, ts.nanosecond)
      var msecs = MSECS_LEN
      if ms.len < MSECS_LEN:
        let leading0 = MSECS_LEN-ms.len
        for n in 0..<leading0:
          destUnchecked.add('0')
        msecs = ms.len
      for n in 0..<msecs:
        destUnchecked.add(ms[n])
    of LF_THREAD_ID.uint8:
      when useThreads:
        if threadId >= 0:
          destUnchecked.add($threadId)
        else:
          destUnchecked.add('-')
          destUnchecked.add('1')
    of LF_PROCESS_ID.uint8:
      if processId >= 0:
        destUnchecked.add($processId)
      else:
        destUnchecked.add('-')
        destUnchecked.add('1')
    of LF_PROCESS_NAME.uint8:
      destUnchecked.add(processName)
    of LF_TAGS.uint8:
      destUnchecked.add('{')
      if tagger.tags.len > 0:
        var notFirst = false
        for k,v in tagger.tags.pairs:
          if notFirst:
            destUnchecked.add(',')
          destUnchecked.add(k)
          destUnchecked.add(':')
          destUnchecked.add(v)
          notFirst = true
      destUnchecked.add('}')
    of LF_MESSAGE.uint8:
      destUnchecked.add(message)
    of LF_HOSTNAME.uint8:
      destUnchecked.add(hostName)
    else:
      destUnchecked.add(code.char)



when useThreads:
  proc build*(
    self: LoggerFormatter, tagger: LoggerTagger,
    level: Level,
    name, hostName, filename, lineno: openArray[char],
    processId: int,
    processName: openArray[char],
    threadId: int,
    message: openArray[char]
  ): string = buildReal(self, tagger, level, name, hostName, filename, lineno, processId, processName, threadId, message)
else:
  proc build*(
    self: LoggerFormatter, tagger: LoggerTagger,
    level: Level,
    name, hostName, filename, lineno: openArray[char],
    processId: int,
    processName: openArray[char],
    message: openArray[char]
  ): string = buildReal(self, tagger, level, name, hostName, filename, lineno, processId, processName, 0, message)
