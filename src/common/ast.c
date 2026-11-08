#include "ast.h"
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

int arrow_nerrors = 0;
const char *arrow_file = "<input>";

void arrow_error(int line, const char *fmt, ...)
{
    va_list ap;
    if (line > 0) fprintf(stderr, "%s:%d: error: ", arrow_file, line);
    else          fprintf(stderr, "%s: error: ", arrow_file);
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    arrow_nerrors++;
}

Node *ast_new(NodeKind kind, int line)
{
    Node *n = calloc(1, sizeof *n);
    if (!n) { fprintf(stderr, "arrow: out of memory\n"); exit(2); }
    n->kind = kind;
    n->line = line;
    n->slot = -1;
    return n;
}

Node *ast_append(Node *list, Node *item)
{
    Node *p;
    if (!list) return item;
    if (!item) return list;
    for (p = list; p->next; p = p->next) ;
    p->next = item;
    return list;
}

int ast_count(Node *list)
{
    int n = 0;
    for (; list; list = list->next) n++;
    return n;
}

const char *op_text(int op)
{
    static const char *t[] = { "+", "-", "*", "/", "%", "<", "<=", ">", ">=", "==", "!=", "&", "|", "neg", "~" };
    return t[op];
}

static const char *kind_text(NodeKind k)
{
    static const char *t[] = {
        "int", "var", "index", "binary", "unary", "call", "read", "new", "array-literal", "len",
        "assign", "show", "loop", "range-loop", "when", "give", "call-stmt", "block", "fn", "param"
    };
    return t[k];
}

void ast_dump(FILE *out, Node *n, int indent)
{
    for (; n; n = n->next) {
        fprintf(out, "%*s%s", indent * 2, "", kind_text(n->kind));
        if (n->name) fprintf(out, " %s", n->name);
        if (n->kind == N_INT) fprintf(out, " %ld", n->ival);
        if (n->kind == N_BIN || n->kind == N_UN) fprintf(out, " %s", op_text(n->op));
        if (n->kind == N_PARAM && n->ival) fprintf(out, " []");
        fprintf(out, "  (line %d)\n", n->line);
        if (n->a) ast_dump(out, n->a, indent + 1);
        if (n->b) ast_dump(out, n->b, indent + 1);
        if (n->c) ast_dump(out, n->c, indent + 1);
    }
}
