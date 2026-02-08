local M = {}

M.names = {}

--- @param item_name string
--- @return string
function M.log_item(item_name)
  return string.format("print(%s)", item_name)
end

--- Python-specific prompt context for AI code generation
--- @return string
function M.prompt_context()
  return [[
PYTHON-SPECIFIC:
- Preserve the exact indentation level of the selection (Python is indentation-sensitive)
- Look at FILE_CONTAINING_SELECTION to understand if the code is inside a function, class, or at module level
- Variables inside functions must be lowercase snake_case (e.g., max_value, not MAX_VALUE)
- Only use UPPER_SNAKE_CASE for module-level constants defined outside functions/classes
- If fixing a linter warning about magic numbers inside a function, use a lowercase variable name
- Only output the replacement for the selection, matching its indentation exactly
]]
end

-- Python standard library modules (from docs.python.org/3/library)
-- Used to skip LSP resolution for stdlib imports
-- stylua: ignore start
M.stdlib_modules = {
  -- Built-in and constants
  "builtins", "__future__", "__main__",
  -- Text Processing
  "string", "re", "difflib", "textwrap", "unicodedata", "stringprep", "readline", "rlcompleter",
  -- Binary Data
  "struct", "codecs",
  -- Data Types
  "datetime", "zoneinfo", "calendar", "collections", "heapq", "bisect", "array", "weakref",
  "types", "copy", "pprint", "reprlib", "enum", "graphlib",
  -- Numeric and Math
  "numbers", "math", "cmath", "decimal", "fractions", "random", "statistics",
  -- Functional Programming
  "itertools", "functools", "operator",
  -- File and Directory
  "pathlib", "os", "io", "stat", "filecmp", "tempfile", "glob", "fnmatch", "linecache", "shutil",
  -- Data Persistence
  "pickle", "copyreg", "shelve", "marshal", "dbm", "sqlite3",
  -- Data Compression
  "zlib", "gzip", "bz2", "lzma", "zipfile", "tarfile", "compression",
  -- File Formats
  "csv", "configparser", "tomllib", "netrc", "plistlib",
  -- Cryptographic
  "hashlib", "hmac", "secrets",
  -- OS Services
  "time", "logging", "platform", "errno", "ctypes",
  -- Concurrent
  "threading", "multiprocessing", "concurrent", "subprocess", "sched", "queue", "contextvars", "_thread",
  -- Networking
  "asyncio", "socket", "ssl", "select", "selectors", "signal", "mmap",
  -- Internet Data
  "email", "json", "mailbox", "mimetypes", "base64", "binascii", "quopri",
  -- Markup
  "html", "xml",
  -- Internet Protocols
  "webbrowser", "wsgiref", "urllib", "http", "ftplib", "poplib", "imaplib", "smtplib",
  "uuid", "socketserver", "xmlrpc", "ipaddress",
  -- Multimedia
  "wave", "colorsys",
  -- Internationalization
  "gettext", "locale",
  -- GUI
  "tkinter", "turtle", "idlelib",
  -- Development
  "typing", "pydoc", "doctest", "unittest", "test",
  -- Debug and Profile
  "bdb", "faulthandler", "pdb", "profile", "cProfile", "timeit", "trace", "tracemalloc",
  -- Packaging
  "ensurepip", "venv", "zipapp", "pip", "setuptools", "distutils",
  -- Runtime
  "sys", "sysconfig", "warnings", "dataclasses", "contextlib", "abc", "atexit",
  "traceback", "gc", "inspect", "site",
  -- Interpreters
  "code", "codeop",
  -- Importing
  "zipimport", "pkgutil", "modulefinder", "runpy", "importlib",
  -- Language Services
  "ast", "symtable", "token", "keyword", "tokenize", "tabnanny", "pyclbr", "py_compile", "compileall", "dis", "pickletools",
  -- Windows
  "msvcrt", "winreg", "winsound",
  -- Unix
  "posix", "pwd", "grp", "termios", "tty", "pty", "fcntl", "resource", "syslog", "shlex",
  -- CLI/Command-line
  "argparse", "optparse", "getopt", "getpass", "fileinput", "curses", "cmd",
  -- Misc internal
  "_string", "_collections", "_functools", "_operator", "_io", "_thread", "_warnings",
  "_weakref", "_abc", "_ast", "_bisect", "_codecs", "_contextvars", "_csv", "_datetime",
  "_decimal", "_elementtree", "_hashlib", "_heapq", "_json", "_locale", "_lzma", "_md5",
  "_pickle", "_posixsubprocess", "_random", "_sha1", "_sha256", "_sha512", "_sha3",
  "_signal", "_socket", "_sqlite3", "_sre", "_ssl", "_stat", "_statistics", "_string",
  "_struct", "_symtable", "_thread", "_tracemalloc", "_uuid", "_warnings", "_weakref",
}
-- stylua: ignore end

--- Check if a module is part of Python's standard library
--- @param module_name string
--- @return boolean
function M.is_stdlib(module_name)
  -- Get the root module (e.g., "os" from "os.path")
  local root = module_name:match("^([^%.]+)")
  if not root then
    return false
  end

  for _, stdlib_mod in ipairs(M.stdlib_modules) do
    if root == stdlib_mod then
      return true
    end
  end
  return false
end

return M
