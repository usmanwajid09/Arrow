/* arrow_rt.c - small C runtime linked into every compiled Arrow program.
 *
 * Array layout: a pointer to a block of 64-bit integers; element 0 holds the
 * length and elements 1..n hold the data.
 */
#include <stdio.h>
#include <stdlib.h>

long arrow_empty[1] = { 0 };    /* the array every never-assigned array variable points to */

static void fail(long line, const char *msg, long x, long y)
{
    fflush(stdout);
    fprintf(stderr, "arrow: runtime error (line %ld): ", line);
    fprintf(stderr, msg, x, y);
    fputc('\n', stderr);
    exit(1);
}

void arrow_oob(long idx, long len, long line)
{
    fail(line, "index %ld out of range for array of length %ld", idx, len);
}

long *arrow_new(long n, long line)
{
    long *p;
    if (n < 0) fail(line, "new[%ld]: array size must not be negative", n, 0);
    if (n > (1L << 40)) fail(line, "new[%ld]: array is too large", n, 0);
    p = calloc((size_t)n + 1, sizeof(long));
    if (!p) fail(line, "new[%ld]: out of memory", n, 0);
    p[0] = n;
    return p;
}

void arrow_show(long v)
{
    printf("%ld\n", v);
}

long arrow_read(long line)
{
    long v;
    if (scanf("%ld", &v) != 1) fail(line, "read(): end of input or not an integer", 0, 0);
    return v;
}

long arrow_div(long a, long b, long line)
{
    if (b == 0) fail(line, "division by zero", 0, 0);
    if (b == -1) return (long)(0UL - (unsigned long)a);
    return a / b;
}

long arrow_mod(long a, long b, long line)
{
    if (b == 0) fail(line, "remainder by zero", 0, 0);
    if (b == -1) return 0;
    return a % b;
}
