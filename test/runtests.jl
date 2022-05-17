using CClosures
using Test

args = [3, 1, 2]

@testset "Invoker" begin
    for n in 1:length(args)+1
        i = CClosures.Invoker{n}()
        @test @inferred i(args[1:n-1]..., +, args[n:end]...) == sum(args)
    end
end

@generated function do_ccall(f, ::Type{ret}, args...) where {ret}
    arg_types = (a <: Ref ? Ptr{Cvoid} : a for a in args)
    arg_type_pairs = (:(args[$i]::$t) for (i, t) in zip(eachindex(args), arg_types))
    quote
        @ccall $(Expr(:$, :f))($(arg_type_pairs...),)::$ret
    end
end

@testset "cclosure" begin
    for n in 1:length(args)+1
        f, d = cclosure(+, n, Int, repeat([Int], length(args)))
        @test do_ccall(f, Int, args[1:n-1]..., d, args[n:end]...) == sum(args)
    end
end

@testset "@cclosure" begin
    f, d = @cclosure (+) Int (self, Int, Int, Int)
    @test do_ccall(f, Int, d, args...) == sum(args)

    f, d = @cclosure (+) Int (Int, Int, Int, self)
    @test do_ccall(f, Int, args..., d) == sum(args)

    f, d = @cclosure (+) Int (Int, self, Int, Int)
    @test do_ccall(f, Int, args[1], d, args[2:end]...) == sum(args)
end

count = Ref(0)

function compare(a, b)::Cint
    count[] += 1
    (a < b) ? -1 : ((a > b) ? +1 : 0)
end

function qsort(a, f, d)
    if Sys.iswindows()
        @ccall qsort_s(a::Ptr{Int}, length(a)::Csize_t, sizeof(eltype(a))::Csize_t, f::Ptr{Cvoid}, d::Ptr{Cvoid})::Cvoid
    elseif Sys.isbsd()
        @ccall qsort_r(a::Ptr{Int}, length(a)::Csize_t, sizeof(eltype(a))::Csize_t, d::Ptr{Cvoid}, f::Ptr{Cvoid})::Cvoid
    elseif Sys.islinux()
        @ccall qsort_r(a::Ptr{Int}, length(a)::Csize_t, sizeof(eltype(a))::Csize_t, f::Ptr{Cvoid}, d::Ptr{Cvoid})::Cvoid
    end
end

@testset "qsort" begin
    a = copy(args)
    @assert !issorted(a)
    ccompare = @cfunction compare Cint (Ref{Int}, Ref{Int})
    @ccall qsort(a::Ptr{Int}, length(a)::Csize_t, sizeof(eltype(a))::Csize_t, ccompare::Ptr{Cvoid})::Cvoid
    @test issorted(a)
    
    a = copy(args)
    if Sys.islinux()
        f, d = @cclosure compare Cint (Ref{Int}, Ref{Int}, self)
    else
        f, d = @cclosure compare Cint (self, Ref{Int}, Ref{Int})
    end
    qsort(a, f, d)
    @test issorted(a)

    count[] = 0
    count2 = Ref(0)
    a = copy(args)
    f, d = cclosure(Sys.islinux() ? 3 : 1, Cint, (Ref{Int}, Ref{Int})) do a, b
        count2[] += 1
        compare(a, b)
    end
    qsort(a, f, d)
    @test issorted(a)
    @test count[] == count2[]
end
