%option noyywrap yylineno nounput noinput
%{
/* lexer.l - Flex scanner for the Arrow language (shared by both phases) */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include "ast.h"
#include "parser.tab.h"

#define YY_USER_ACTION \
    yylloc.first_line = yylloc.last_line = yylineno; \
    yylloc.first_column = yylloc.last_column = 0;
%}

ID      [A-Za-z_][A-Za-z_0-9]*

%%

[ \t\r\n]+              { /* skip white space */ }
"--".*                  { /* comment to end of line */ }

"fn"                    { return FN; }
"loop"                  { return LOOP; }
"in"                    { return IN; }
"when"                  { return WHEN; }
"otherwise"             { return OTHERWISE; }
"give"                  { return GIVE; }
"show"                  { return SHOW; }
"new"                   { return NEW; }
"len"                   { return LEN; }
"read"                  { return READ; }

{ID}                    { yylval.str = strdup(yytext); return ID; }

[0-9]+                  {
                            errno = 0;
                            yylval.ival = strtol(yytext, NULL, 10);
                            if (errno == ERANGE) {
                                arrow_error(yylineno, "integer literal '%s' is too large", yytext);
                                yylval.ival = 0;
                            }
                            return INT;
                        }

"=>"                    { return ARROW; }
".."                    { return DOTDOT; }
"<="                    { return LE; }
">="                    { return GE; }
"=="                    { return EQ; }
"!="                    { return NE; }

[-+*/%<>&|~()\[\]{},;]  { return yytext[0]; }

"="                     { arrow_error(yylineno, "unexpected '=': use '=>' to assign and '==' to compare"); }
.                       { arrow_error(yylineno, "unexpected character '%s'", yytext); }

%%
