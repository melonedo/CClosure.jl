module CClosure
export cclosure

struct Invoker{N} end

function (::Invoker{N})(args...) where {N}
    # signature `Ref` already loads `f`
    args[N](args[1:N-1]..., args[N+1:end]...)
end

unwrap(::Type{Type{T}}) where {T} = T

@generated function cfunction_invoker(::Val{n}, ret, args...) where {n}
    quote
        # can not use `$Invoker{$n}`
        @cfunction $(Invoker{n}()) $(unwrap(ret)) ($(unwrap.(args)...),)
    end
end


"""
    cclosure(callable, n, ReturnType, (ArgumentTypes...)) -> func_ptr, Ref(callable)

Accepts arguments as [`@cfunction`](https://docs.julialang.org/en/v1/base/c/#Base.@cfunction)
plus an **extra** context pointer at position `n`.

Return `func_ptr` that expects the `context_ptr` to be passed as at position `n`
and a reference to callable, which must be `GC.@preserve`d if not directly used in `ccall`.

# Examples
```julia-repl
julia> f(x, y) = 
    let left, right
        func, ctx = cclosure(3, Int, (Int, Int)) do a, b
            left = a
            right = b
            a + b
        end
        sum = @ccall \$func(x::Int, y::Int, ctx::Ptr{Cvoid})::Int
        left, right, sum
    end
f (generic function with 1 method)

julia> f(1, 2)
(1, 2, 3)
```
"""
@inline function cclosure(func, n, ret, args)
    pfunc::Ptr{Cvoid} = cfunction_invoker(Val(n), ret, args[1:n-1]..., Ref{typeof(func)}, args[n:end]...)
    pdata = Ref(func)
    pfunc, pdata
end

end
