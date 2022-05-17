module CClosures
export cclosure, @cclosure

struct Invoker{N} end

function (::Invoker{N})(args...) where {N}
    # signature `Ref` already loads `f`
    # f = unsafe_load(Ptr{Func}(args[N]))
    args[N](args[1:N-1]..., args[N+1:end]...)
end

unwrap(::Type{Type{T}}) where {T} = T

@generated function cfunction_invoker(::Val{n}, ret, args...) where {n}
    quote
        # can not use `$Invoker{$n}``
        @cfunction $(Invoker{n}()) $(unwrap(ret)) ($(unwrap.(args)...),)
    end
end


"""
    cclosure(callable, n, ReturnType, (ArgumentTypes...))

Accepts arguments as [`@cfunction`](https://docs.julialang.org/en/v1/base/c/#Base.@cfunction), 
except an extra context pointer will be inserted at position `n`.

Return `func_ptr` that expects the `context_ptr` to be passed as at position `n`.
"""
function cclosure(func, n, ret, args)
    pfunc = cfunction_invoker(Val(n), ret, args[1:n-1]..., Ref{typeof(func)}, args[n:end]...)
    pdata = Ref(func)
    pfunc, pdata
end

function cclosure_impl(func, ret, old_args)
    n = 0
    @assert old_args isa Expr && old_args.head == :tuple
    args = []
    for (i, arg) in enumerate(old_args.args)
        if arg == :self
            n = i
            continue
        end
        push!(args, arg)
    end
    n == 0 && error("Must include a parameter named `self` as context")
    quote
        $cclosure($func, $n, $ret, ($(args...),))
    end |> esc
end


"""
    @cclosure callable ReturnType (ArgumentTypes...) -> func_ptr, context_ptr

Accepts arguments as [`@cfunction`](https://docs.julialang.org/en/v1/base/c/#Base.@cfunction), 
except one of argument type must be specified as `self`.

Return `func_ptr` that expects the `context_ptr` to be passed as specified in `self`.
"""
macro cclosure(func, ret, args)
    cclosure_impl(func, ret, args)
end

end
