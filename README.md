# CClosure

[![Build Status](https://github.com/melonedo/CClosure.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/melonedo/CClosure.jl/actions/workflows/CI.yml?query=branch%3Amain)

`cclosure` is a wrapper of `@cfunction` that supports closures on all platforms and works on local variables.
Instead of relying on LLVM trampolines, `cclosure` creates classical C closure: a pair of function pointer and a context pointer, where context is explicitly passed to the function pointer by an external C libray.

# Callback with `qsort`

All systems that Julia supports have a version of `qsort` that supports the classical C closure, although they have different signature. On [Windows](https://docs.microsoft.com/en-us/cpp/c-runtime-library/reference/qsort-s?view=msvc-170), it is defined as:

```c
typedef int (*callback)(void *context, const void *left, const void *right);
void qsort_s(void *base, size_t num, size_t width, callback compare, void *context);
```

See [`qsort` on other platforms](#qsort-on-other-platforms) if you are not on Windows.

The signatures can be translated to Julia:

```julia
using CClosure
function qsort_c(a, func, ctx)
    @ccall qsort_s(a::Ptr{Cvoid}, length(a)::Csize_t, sizeof(eltype(a))::Csize_t, func::Ptr{Cvoid}, ctx::Ptr{Cvoid})::Cvoid
end
compare(a, b)::Cint = a > b ? +1 : a < b ? -1 : 0
```

Now we can write a comparator that accepts arbitrary Julia functions:

```julia
function qsort_log_cclosure(a)
    T = eltype(a)
    log = Tuple{T, T}[]
    func, ctx = cclosure(1, Cint, (Ref{T}, Ref{T})) do a, b
        push!(log, (a, b))
        compare(a, b)
    end
    qsort_c(a, func, ctx)
    log, a
end
qsort_log_cclosure([3,2,1])
```

Note that `Ref{T}` in `@cfunction` (and thus `cclosure`) tells Julia to load the pointer of type `T` for you.

### Without `cclosure`

For comparison, without `cclosure` it is usually written either as a monolithic piece:

```julia
function compare_log(log, a, b)
    push!(log, (a, b))
    compare(a, b)
end
function qsort_log_monolithic(a::Vector{Int})
    log = Tuple{Int,Int}[]
    func = @cfunction compare_log Cint (Ref{Vector{Tuple{Int,Int}}}, Ref{Int}, Ref{Int})
    ctx = Ref(log)
    qsort_c(a, func, ctx)
    log, a
end
qsort_log_monolithic([3,2,1])
```

... or type-unstable:

```julia
function compare_unstable(p, a, b)
    f = unsafe_pointer_to_objref(p)[]
    f(a, b)
end
function qsort_log_unstable(a)
    T = eltype(a)
    log = Tuple{T, T}[]
    ctx = function (a, b)
        a = unsafe_load(Ptr{T}(a))
        b = unsafe_load(Ptr{T}(b))
        push!(log, (a, b))
        compare(a, b)
    end
    func = @cfunction compare_unstable Cint (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid})
    qsort_c(a, func, Ref(ctx))
    log, a
end
qsort_log_unstable([3,2,1])
```

In any case you need another global function visible to `@cfunction`.


### `qsort` on other platforms

[Linux](https://linux.die.net/man/3/qsort_r) and [C11](https://en.cppreference.com/w/c/algorithm/qsort) (Julia is built with C89 so this is only for reference)
```c
typedef int (*callback)(const void *left, const void *right, void *context);
void qsort_r(void *base, size_t num, size_t width, callback compare, void *context);
```

[BSD](https://www.freebsd.org/cgi/man.cgi?query=qsort_r&sektion=3)
```c
typedef int (*callback)(void *context, const void *left, const void *right);
void qsort_r(void *base, size_t num, size_t width, void *context, callback compare);
```

## Typedef

If you feel like exposing C `typedef` to Julia, you can write:

```julia
# add parameter `T` because callback is generic
callback(f, T) = cclosure(f, 1, Cint, (Ref{T}, Ref{T}))
# used as 
func, ctx = callback(T) do a, b
    ...
end
```

## Storing closures

In `func, ctx = cclosure(f, ...)`, `func` is alive for the current Julia session, while `ctx` holds reference to `f` and must be kept alive when the callback is called which is already done by `ccall`. So you should GC-root `ctx` when you store the callback in C structs as a pair of pointers.

