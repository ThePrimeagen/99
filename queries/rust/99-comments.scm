; Regular line comments (//)
(line_comment) @context.comment

; Block comments (/* */)
(block_comment) @context.comment

; Note: Doc comments (///, //!, /** */, /*! */) are also captured by
; line_comment and block_comment nodes. The doc comment markers are
; children of these nodes, so we capture all comments uniformly.
