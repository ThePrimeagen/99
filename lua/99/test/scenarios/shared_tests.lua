local M = {}

M.simple_function = {
    c = {
        code = { "int add(int a, int b) {", "}" },
        row = 1,
        col = 0,
        check = "int add(int a, int b) {",
        resolve = "int add(int a, int b) {\n    return a + b;\n}",
        expect = { "int add(int a, int b) {", "    return a + b;", "}" },
    },
    python = {
        code = { "def greet(name):", "    pass" },
        row = 1,
        col = 0,
        check = "def greet(name):",
        resolve = 'def greet(name):\n    return f"Hello, {name}!"',
        expect = { "def greet(name):", '    return f"Hello, {name}!"' },
    },
    go = {
        code = { "package main", "", "func greet(name string) string {", "}" },
        row = 3,
        col = 0,
        check = "func greet(name string) string {",
        resolve = 'func greet(name string) string {\n\treturn "Hello, " + name\n}',
        expect = {
            "package main",
            "",
            "func greet(name string) string {",
            '\treturn "Hello, " + name',
            "}",
        },
    },
    ruby = {
        code = { "def greet(name)", "end" },
        row = 1,
        col = 0,
        check = "def greet(name)",
        resolve = 'def greet(name)\n  "Hello, #{name}!"\nend',
        expect = { "def greet(name)", '  "Hello, #{name}!"', "end" },
    },
    rust = {
        code = { "fn greet(name: &str) -> String {", "}" },
        row = 1,
        col = 0,
        check = "fn greet(name: &str) -> String {",
        resolve = 'fn greet(name: &str) -> String {\n    format!("Hello, {}!", name)\n}',
        expect = {
            "fn greet(name: &str) -> String {",
            '    format!("Hello, {}!", name)',
            "}",
        },
    },
    lua = {
        code = { "function greet(name)", "end" },
        row = 1,
        col = 0,
        check = "function greet(name)",
        resolve = 'function greet(name)\n    return "Hello, " .. name\nend',
        expect = {
            "function greet(name)",
            '    return "Hello, " .. name',
            "end",
        },
    },
    typescript = {
        code = { "function greet(name: string): string {", "}" },
        row = 1,
        col = 0,
        check = "function greet(name: string): string {",
        resolve = "function greet(name: string): string {\n    return `Hello, ${name}!`;\n}",
        expect = {
            "function greet(name: string): string {",
            "    return `Hello, ${name}!`;",
            "}",
        },
    },
}

M.single_comment = {
    c = {
        code = {
            "// Adds two integers together",
            "int add(int a, int b) {",
            "}",
        },
        row = 2,
        col = 0,
        check = "// Adds two integers together",
    },
    python = {
        code = {
            "# This function greets a user",
            "def greet(name):",
            "    pass",
        },
        row = 2,
        col = 0,
        check = "# This function greets a user",
    },
    go = {
        code = {
            "package main",
            "",
            "// Greet returns a greeting message",
            "func greet(name string) string {",
            "}",
        },
        row = 4,
        col = 0,
        check = "// Greet returns a greeting message",
    },
    ruby = {
        code = { "# Greets the user by name", "def greet(name)", "end" },
        row = 2,
        col = 0,
        check = "# Greets the user by name",
    },
    rust = {
        code = {
            "/// Greets the user by name",
            "fn greet(name: &str) -> String {",
            "}",
        },
        row = 2,
        col = 0,
        check = "/// Greets the user by name",
    },
    lua = {
        code = { "-- Greets the user by name", "function greet(name)", "end" },
        row = 2,
        col = 0,
        check = "-- Greets the user by name",
    },
    typescript = {
        code = {
            "// Process the input data",
            "function process(data: Buffer): void {",
            "}",
        },
        row = 2,
        col = 0,
        check = "// Process the input data",
    },
}

M.multi_line_comment = {
    c = {
        code = {
            "/*",
            " * Process the data",
            " * and return the result",
            " */",
            "int process(int* data, int len) {",
            "}",
        },
        row = 5,
        col = 0,
        checks = { "Process the data" },
    },
    python = {
        code = {
            "# First line of documentation",
            "# Second line",
            "def process(data):",
            "    pass",
        },
        row = 3,
        col = 0,
        checks = { "# First line of documentation", "# Second line" },
    },
    go = {
        code = {
            "package main",
            "",
            "// Process handles the data",
            "// and returns the result",
            "func process(data []byte) error {",
            "}",
        },
        row = 5,
        col = 0,
        checks = { "// Process handles the data", "// and returns the result" },
    },
    ruby = {
        code = {
            "# Process the input data",
            "# and return the result",
            "def process(data)",
            "end",
        },
        row = 3,
        col = 0,
        checks = { "# Process the input data", "# and return the result" },
    },
    rust = {
        code = {
            "/// Process the input data",
            "/// and return the result",
            "fn process(data: &[u8]) -> Result<(), Error> {",
            "}",
        },
        row = 3,
        col = 0,
        checks = { "/// Process the input data", "/// and return the result" },
    },
    lua = {
        code = {
            "-- Process the input",
            "-- and return result",
            "function process(data)",
            "end",
        },
        row = 3,
        col = 0,
        checks = { "-- Process the input", "-- and return result" },
    },
    typescript = {
        code = {
            "/** Greets the user by name */",
            "function greet(name: string): string {",
            "}",
        },
        row = 2,
        col = 0,
        checks = { "/** Greets the user by name */" },
    },
}

M.simple_request = {
    c = { code = { "void cancel_me(void) {", "}" }, row = 1, col = 0 },
    python = { code = { "def cancel_me():", "    pass" }, row = 1, col = 0 },
    go = {
        code = { "package main", "", "func cancelMe() {", "}" },
        row = 3,
        col = 0,
    },
    ruby = { code = { "def cancel_me", "end" }, row = 1, col = 0 },
    rust = { code = { "fn cancel_me() {", "}" }, row = 1, col = 0 },
    lua = { code = { "function cancel_me()", "end" }, row = 1, col = 0 },
    typescript = {
        code = { "function cancelMe(): void {", "}" },
        row = 1,
        col = 0,
    },
}

-- Partial language coverage tests
M.async_function = {
    python = {
        code = { "async def fetch_data(url):", "    pass" },
        row = 1,
        col = 0,
        check = "async def fetch_data(url):",
        resolve = "async def fetch_data(url):\n    return await http.get(url)",
        expect = {
            "async def fetch_data(url):",
            "    return await http.get(url)",
        },
    },
    rust = {
        code = {
            "async fn fetch_data(url: &str) -> Result<String, Error> {",
            "}",
        },
        row = 1,
        col = 0,
        check = "async fn fetch_data(url: &str)",
        resolve = "async fn fetch_data(url: &str) -> Result<String, Error> {\n    Ok(url.to_string())\n}",
        expect = {
            "async fn fetch_data(url: &str) -> Result<String, Error> {",
            "    Ok(url.to_string())",
            "}",
        },
    },
    typescript = {
        code = {
            "async function fetchData(url: string): Promise<string> {",
            "}",
        },
        row = 1,
        col = 0,
        check = "async function fetchData(url: string)",
        resolve = "async function fetchData(url: string): Promise<string> {\n    return await fetch(url);\n}",
        expect = {
            "async function fetchData(url: string): Promise<string> {",
            "    return await fetch(url);",
            "}",
        },
    },
}

M.enclosing_class = {
    python = {
        code = {
            "class Calculator:",
            "    def __init__(self):",
            "        self.value = 0",
            "",
            "    def add(self, n):",
            "        pass",
        },
        row = 5,
        col = 4,
        ctx_check = "class Calculator:",
        fn_check = "def add(self, n):",
        resolve = "def add(self, n):\n        self.value += n",
        expect = {
            "class Calculator:",
            "    def __init__(self):",
            "        self.value = 0",
            "",
            "    def add(self, n):",
            "        self.value += n",
        },
    },
    ruby = {
        code = {
            "class Calculator",
            "  def initialize",
            "    @value = 0",
            "  end",
            "",
            "  def add(n)",
            "  end",
            "end",
        },
        row = 6,
        col = 2,
        ctx_check = "class Calculator",
        fn_check = "def add(n)",
        resolve = "def add(n)\n    @value += n\n  end",
        expect = {
            "class Calculator",
            "  def initialize",
            "    @value = 0",
            "  end",
            "",
            "  def add(n)",
            "    @value += n",
            "  end",
            "end",
        },
    },
    typescript = {
        code = {
            "class Calculator {",
            "    private value: number = 0;",
            "",
            "    add(n: number): void {",
            "    }",
            "}",
        },
        row = 4,
        col = 4,
        ctx_check = "class Calculator",
        fn_check = "add(n: number): void {",
        resolve = "add(n: number): void {\n        this.value += n;\n    }",
        expect = {
            "class Calculator {",
            "    private value: number = 0;",
            "",
            "    add(n: number): void {",
            "        this.value += n;",
            "    }",
            "}",
        },
    },
}

M.closure = {
    go = {
        code = {
            "package main",
            "",
            "func main() {",
            "\tdouble := func(x int) int {",
            "\t}",
            "}",
        },
        row = 4,
        col = 12,
        check = "func(x int) int {",
        resolve = "func(x int) int {\n\t\treturn x * 2\n\t}",
        expect = {
            "package main",
            "",
            "func main() {",
            "\tdouble := func(x int) int {",
            "\t\treturn x * 2",
            "\t}",
            "}",
        },
    },
    rust = {
        code = {
            "fn main() {",
            "    let double = |x: i32| -> i32 {",
            "    };",
            "}",
        },
        row = 2,
        col = 18,
        check = "|x: i32| -> i32 {",
        resolve = "|x: i32| -> i32 {\n        x * 2\n    }",
        expect = {
            "fn main() {",
            "    let double = |x: i32| -> i32 {",
            "        x * 2",
            "    };",
            "}",
        },
    },
}

return M
