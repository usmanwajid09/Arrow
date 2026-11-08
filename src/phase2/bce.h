#ifndef ARROW_BCE_H
#define ARROW_BCE_H
#include "ast.h"

/* Bounds-check elimination: marks N_INDEX nodes whose index is provably inside
   the array (node->safe = 1) so the code generator can omit the run-time check.
   Returns the number of array accesses seen and, through *eliminated, how many
   checks were removed. */
int bce_run(Node *program, int *eliminated);

#endif
