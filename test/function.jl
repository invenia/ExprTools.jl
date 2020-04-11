"""
    @audit expr -> Tuple{Any,Expr}

Evaluate the expression and return both the result and the original expression. Useful for
ensuring that the provided expression is syntactically valid. If provided expression cannot
be evaluated the exception will be returned instead of the result.
"""
macro audit(expr::Expr)
    result = quote
        tuple(
            try
                @eval let
                    $expr
                end
            catch e
                e
            end,
            $(QuoteNode(expr)),
        )
    end
    return esc(result)
end

macro expr(expr::Expr)
    esc(QuoteNode(expr))
end

function strip_lineno!(expr::Expr)
    filter!(expr.args) do ex
        isa(ex, LineNumberNode) && return false
        if isa(ex, Expr)
            ex.head === :line && return false
            strip_lineno!(ex::Expr)
        end
        return true
    end
    return expr
end

macro test_splitdef_invalid(expr)
    result = quote
        @test_throws ArgumentError splitdef($expr)
        @test splitdef($expr, throw=false) === nothing
    end
    return esc(result)
end

function_form(short::Bool) = string(short ? "short" : "long", "-form")


@testset "splitdef / combinedef" begin
    @testset "empty function" begin
        f, expr = @audit function f end
        @test length(methods(f)) == 0

        d = splitdef(expr)
        @test keys(d) == Set([:head, :name])
        @test d[:head] == :function
        @test d[:name] == :f

        c_expr = combinedef(d)
        @test c_expr == expr
    end

    @testset "long-form function" begin
        f, expr = @audit function f() end
        @test length(methods(f)) == 1
        @test f() === nothing

        d = splitdef(expr)
        @test keys(d) == Set([:head, :name, :body])
        @test d[:head] == :function
        @test d[:name] == :f
        @test strip_lineno!(d[:body]) == Expr(:block)

        c_expr = combinedef(d)
        @test c_expr == expr
    end

    @testset "short-form function" begin
        f, expr = @audit f() = nothing
        @test length(methods(f)) == 1
        @test f() === nothing

        d = splitdef(expr)
        @test keys(d) == Set([:head, :name, :body])
        @test d[:head] == :(=)
        @test d[:name] == :f
        @test strip_lineno!(d[:body]) == Expr(:block, :nothing)

        c_expr = combinedef(d)
        @test c_expr == expr
    end

    @testset "long-form anonymous function" begin
        f, expr = @audit function () end
        @test length(methods(f)) == 1
        @test f() === nothing

        d = splitdef(expr)
        @test keys(d) == Set([:head, :body])
        @test d[:head] == :function
        @test strip_lineno!(d[:body]) == Expr(:block)

        c_expr = combinedef(d)
        @test c_expr == expr
    end

    @testset "short-form anonymous function" begin
        f, expr = @audit () -> nothing
        @test length(methods(f)) == 1
        @test f() === nothing

        d = splitdef(expr)
        @test keys(d) == Set([:head, :body])
        @test d[:head] == :(->)
        @test strip_lineno!(d[:body]) == Expr(:block, :nothing)

        c_expr = combinedef(d)
        @test c_expr == expr
    end

    @testset "args ($(function_form(short)) function)" for short in (true, false)
        @testset "f(x)" begin
            f, expr = if short
                @audit f(x) = x
            else
                @audit function f(x) x end
            end
            @test length(methods(f)) == 1
            @test f(0) == 0

            d = splitdef(expr)
            @test keys(d) == Set([:head, :name, :args, :body])
            @test d[:args] == [:x]

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "f(x::Integer)" begin
            f, expr = if short
                @audit f(x::Integer) = x
            else
                @audit function f(x::Integer) x end
            end
            @test length(methods(f)) == 1
            @test f(0) == 0

            d = splitdef(expr)
            @test keys(d) == Set([:head, :name, :args, :body])
            @test d[:args] == [:(x::Integer)]

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "f(x=1)" begin
            f, expr = if short
                @audit f(x=1) = x
            else
                @audit function f(x=1) x end
            end
            @test length(methods(f)) == 2
            @test f(0) == 0
            @test f() == 1

            d = splitdef(expr)
            @test keys(d) == Set([:head, :name, :args, :body])
            @test d[:args] == [Expr(:kw, :x, 1)]

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "f(x::Integer=1)" begin
            f, expr = if short
                @audit f(x::Integer=1) = x
            else
                @audit function f(x::Integer=1) x end
            end
            @test length(methods(f)) == 2
            @test f(0) == 0
            @test f() == 1

            d = splitdef(expr)
            @test keys(d) == Set([:head, :name, :args, :body])
            @test d[:args] == [Expr(:kw, :(x::Integer), 1)]

            c_expr = combinedef(d)
            @test c_expr == expr
        end
    end

    @testset "args ($(function_form(short)) anonymous function)" for short in (true, false)
        @testset "x" begin
            f, expr = if short
                @audit x -> x
            else
                @audit function (x) x end
            end
            @test length(methods(f)) == 1
            @test f(0) == 0

            d = splitdef(expr)
            @test keys(d) == Set([:head, :args, :body])
            @test d[:args] == [:x]

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "x::Integer" begin
            f, expr = if short
                @audit x::Integer -> x
            else
                @audit function (x::Integer) x end
            end
            @test length(methods(f)) == 1
            @test f(0) == 0

            d = splitdef(expr)
            @test keys(d) == Set([:head, :args, :body])
            @test d[:args] == [:(x::Integer)]

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "(x=1)" begin
            f, expr = if short
                @audit (x=1) -> x
            else
                @audit function (x=1) x end
            end
            @test length(methods(f)) == 2
            @test f(0) == 0
            @test f() == 1

            d = splitdef(expr)
            @test keys(d) == Set([:head, :args, :body])
            @test d[:args] == [:(x=1)]

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "(x::Integer=1)" begin
            f, expr = if short
                @audit (x::Integer=1) -> x
            else
                @audit function (x::Integer=1) x end
            end
            @test length(methods(f)) == 2
            @test f(0) == 0
            @test f() == 1

            d = splitdef(expr)
            @test keys(d) == Set([:head, :args, :body])
            @test d[:args] == [:(x::Integer=1)]

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "(x,)" begin
            f, expr = if short
                @audit (x,) -> x
            else
                @audit function (x,) x end
            end
            @test length(methods(f)) == 1
            @test f(0) == 0

            d = splitdef(expr)
            @test keys(d) == Set([:head, :args, :body])
            @test d[:args] == [:x]

            c_expr = combinedef(d)
            expr = short ? (@expr x -> x) : (@expr function (x) x end)
            @test strip_lineno!(c_expr) == strip_lineno!(expr)
        end

        @testset "(x::Integer,)" begin
            f, expr = if short
                @audit (x::Integer,) -> x
            else
                @audit function (x::Integer,) x end
            end
            @test length(methods(f)) == 1
            @test f(0) == 0

            d = splitdef(expr)
            @test keys(d) == Set([:head, :args, :body])
            @test d[:args] == [:(x::Integer)]

            c_expr = combinedef(d)
            expr = short ? (@expr x::Integer -> x) : (@expr function (x::Integer) x end)
            @test strip_lineno!(c_expr) == strip_lineno!(expr)
        end

        @testset "(x=1,)" begin
            f, expr = if short
                @audit (x=1,) -> x
            else
                @audit function (x=1,) x end
            end
            @test length(methods(f)) == 2
            @test f(0) === 0
            @test f() === 1

            d = splitdef(expr)
            @test keys(d) == Set([:head, :args, :body])
            @test d[:args] == [:(x=1)]

            c_expr = combinedef(d)
            expr = short ? (@expr (x=1) -> x) : (@expr function (x=1) x end)
            @test strip_lineno!(c_expr) == strip_lineno!(expr)
        end

        @testset "(x::Integer=1,)" begin
            f, expr = if short
                @audit (x::Integer=1,) -> x
            else
                @audit function (x::Integer=1,) x end
            end
            @test length(methods(f)) == 2
            @test f(0) == 0
            @test f() == 1

            d = splitdef(expr)
            @test keys(d) == Set([:head, :args, :body])
            @test d[:args] == [:(x::Integer=1)]

            c_expr = combinedef(d)
            expr = short ? (@expr (x::Integer=1) -> x) : (@expr function (x::Integer=1) x end)
            @test strip_lineno!(c_expr) == strip_lineno!(expr)
        end
    end

    @testset "kwargs ($(function_form(short)) function)" for short in (true, false)
        @testset "f(; x)" begin
            f, expr = if short
                @audit f(; x) = x
            else
                @audit function f(; x) x end
            end
            @test length(methods(f)) == 1
            @test f(x=0) == 0

            d = splitdef(expr)
            @test keys(d) == Set([:head, :name, :kwargs, :body])
            @test d[:kwargs] == [:x]

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "f(; x::Integer)" begin
            f, expr = if short
                @audit f(; x::Integer) = x
            else
                @audit function f(; x::Integer) x end
            end
            @test length(methods(f)) == 1
            @test f(x=0) == 0

            d = splitdef(expr)
            @test keys(d) == Set([:head, :name, :kwargs, :body])
            @test d[:kwargs] == [:(x::Integer)]

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "f(; x=1)" begin
            f, expr = if short
                @audit f(; x=1) = x
            else
                @audit function f(; x=1) x end
            end
            @test length(methods(f)) == 1
            @test f(x=0) == 0

            d = splitdef(expr)
            @test keys(d) == Set([:head, :name, :kwargs, :body])
            @test d[:kwargs] == [Expr(:kw, :x, 1)]

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "f(; x::Integer=1)" begin
            f, expr = if short
                @audit f(; x::Integer=1) = x
            else
                @audit function f(; x::Integer=1) x end
            end
            @test length(methods(f)) == 1
            @test f(x=0) == 0

            d = splitdef(expr)
            @test keys(d) == Set([:head, :name, :kwargs, :body])
            @test d[:kwargs] == [Expr(:kw, :(x::Integer), 1)]

            c_expr = combinedef(d)
            @test c_expr == expr
        end
    end

    @testset "kwargs ($(function_form(short)) function)" for short in (true, false)
        @testset "(; x)" begin
            f, expr = if short
                @audit (; x) -> x
            else
                @audit function (; x) x end
            end
            @test length(methods(f)) == 1
            @test f(x=0) == 0

            d = splitdef(expr)
            @test keys(d) == Set([:head, :kwargs, :body])
            @test d[:kwargs] == [:x]

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "(; x::Integer)" begin
            f, expr = if short
                @audit (; x::Integer) -> x
            else
                @audit function (; x::Integer) x end
            end
            @test length(methods(f)) == 1
            @test f(x=0) == 0

            d = splitdef(expr)
            @test keys(d) == Set([:head, :kwargs, :body])
            @test d[:kwargs] == [:(x::Integer)]

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "(; x=1)" begin
            f, expr = if short
                @audit (; x=1) -> x
            else
                @audit function (; x=1) x end
            end
            @test length(methods(f)) == 1
            @test f(x=0) == 0

            d = splitdef(expr)
            @test keys(d) == Set([:head, :kwargs, :body])
            @test d[:kwargs] == [Expr(:kw, :x, 1)]

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "(; x::Integer=1)" begin
            f, expr = if short
                @audit (; x::Integer=1) -> x
            else
                @audit function (; x::Integer=1) x end
            end
            @test length(methods(f)) == 1
            @test f(x=0) == 0

            d = splitdef(expr)
            @test keys(d) == Set([:head, :kwargs, :body])
            @test d[:kwargs] == [Expr(:kw, :(x::Integer), 1)]

            c_expr = combinedef(d)
            @test c_expr == expr
        end
    end

    # When using :-> there are a few definitions that use a block expression instead of the
    # typical tuple.
    @testset "block expression ($(function_form(short)) anonymous function)" for short in (true, false)
        @testset "(;)" begin
            # The `(;)` syntax was deprecated in 1.4.0-DEV.585 (ce29ec547e) but we can still
            # test the behavior with `begin end`.
            f, expr = if short
                @audit (begin end) -> nothing
            else
                @audit function (begin end) nothing end
            end
            @test length(methods(f)) == 1
            @test f() === nothing

            # Note: the semi-colon is missing from the expression
            d = splitdef(expr)
            @test keys(d) == Set([:head, :kwargs, :body])
            @test d[:kwargs] == []

            c_expr = combinedef(d)
            expr = Expr(:->, Expr(:tuple, Expr(:parameters)), Expr(:block, :nothing))
            expr.head = short ? :-> : :function
            @test strip_lineno!(c_expr) == strip_lineno!(expr)
        end

        @testset "(x;)" begin
            f, expr = if short
                @audit (x;) -> x
            else
                @audit function (x;) x end
            end
            @test length(methods(f)) == 1
            @test f(0) == 0

            # Note: the semi-colon is missing from the expression
            d = splitdef(expr)
            @test keys(d) == Set([:head, :args, :kwargs, :body])
            @test d[:args] == [:x]
            @test d[:kwargs] == []

            c_expr = combinedef(d)
            expr = Expr(:->, Expr(:tuple, Expr(:parameters), :x), Expr(:block, :x))
            expr.head = short ? :-> : :function
            @test strip_lineno!(c_expr) == strip_lineno!(expr)
        end

        @testset "(x; y)" begin
            f, expr = if short
                @audit (x; y) -> (x, y)
            else
                @audit function (x; y); (x, y) end
            end
            @test length(methods(f)) == 1
            @test f(0, y=1) == (0, 1)

            # Note: the semi-colon is missing from the expression
            d = splitdef(expr)
            @test keys(d) == Set([:head, :args, :kwargs, :body])
            @test d[:args] == [:x]
            @test d[:kwargs] == [:y]

            c_expr = combinedef(d)
            expr = Expr(:->, Expr(:tuple, Expr(:parameters, :y), :x), Expr(:block, :((x, y))))
            expr.head = short ? :-> : :function
            @test strip_lineno!(c_expr) == strip_lineno!(expr)
        end

        @testset "(x; y = 0)" begin
            f, expr = if short
                @audit (x; y = 0) -> (x, y)
            else
                @audit function (x; y = 0); (x, y) end
            end
            @test length(methods(f)) == 1
            @test f(0) == (0, 0)
            @test f(0, y=1) == (0, 1)

            # Note: the semi-colon is missing from the expression
            d = splitdef(expr)
            @test keys(d) == Set([:head, :args, :kwargs, :body])
            @test d[:args] == [:x]
            @test d[:kwargs] == [Expr(:kw, :y, 0)]

            c_expr = combinedef(d)
            expr = Expr(:->, Expr(:tuple, Expr(:parameters, Expr(:kw, :y, 0)), :x), Expr(:block, :((x, y))))
            expr.head = short ? :-> : :function
            @test strip_lineno!(c_expr) == strip_lineno!(expr)
        end

        @testset "(x; y = 0, _...)" begin
            f, expr = if short
                @audit (x; y = 0, _...) -> (x, y)
            else
                @audit function (x; y = 0, _...); (x, y) end
            end
            @test length(methods(f)) == 1
            @test f(0) == (0, 0)
            @test f(0, y=1) == (0, 1)
            @test f(0, y=1, z=2) == (0, 1)

            # Note: the semi-colon is missing from the expression
            d = splitdef(expr)
            @test keys(d) == Set([:head, :args, :kwargs, :body])
            @test d[:args] == [:x]
            @test d[:kwargs] == [Expr(:kw, :y, 0), :(_...)]

            c_expr = combinedef(d)
            expr = Expr(:->, Expr(:tuple, Expr(:parameters, Expr(:kw, :y, 0), :(_...)), :x), Expr(:block, :((x, y))))
            expr.head = short ? :-> : :function
            @test strip_lineno!(c_expr) == strip_lineno!(expr)
        end

        @testset "Expr(:block, :x, :y)" begin
            expr = Expr(:->, Expr(:block, :x, :y), Expr(:block, :((x, y))))
            expr.head = short ? :-> : :function
            f = @eval $expr
            @test length(methods(f)) == 1
            @test f(0, y=1) == (0, 1)

            # Note: the semi-colon is missing from the expression
            d = splitdef(expr)
            @test keys(d) == Set([:head, :args, :kwargs, :body])
            @test d[:args] == [:x]
            @test d[:kwargs] == [:y]

            c_expr = combinedef(d)
            expr = Expr(:->, Expr(:tuple, Expr(:parameters, :y), :x), Expr(:block, :((x, y))))
            expr.head = short ? :-> : :function
            @test strip_lineno!(c_expr) == strip_lineno!(expr)
        end
    end

    @testset "where ($(function_form(short)) function)" for short in (true, false)
        @testset "single where" begin
            f, expr = if short
                @audit f(::A) where A = nothing
            else
                @audit function f(::A) where A; nothing end
            end
            @test length(methods(f)) == 1

            d = splitdef(expr)
            @test keys(d) == Set([:head, :name, :args, :whereparams, :body])
            @test d[:whereparams] == [:A]

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "curly where" begin
            f, expr = if short
                @audit f(::A, ::B) where {A, B <: A} = nothing
            else
                @audit function f(::A, ::B) where {A, B <: A}; nothing end
            end
            @test length(methods(f)) == 1

            d = splitdef(expr)
            @test keys(d) == Set([:head, :name, :args, :whereparams, :body])
            @test d[:whereparams] == [:A, :(B <: A)]

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "multiple where" begin
            f, expr = if short
                @audit f(::A, ::B) where B <: A where A = nothing
            else
                @audit function f(::A, ::B) where B <: A where A; nothing end
            end
            @test length(methods(f)) == 1

            d = splitdef(expr)
            @test keys(d) == Set([:head, :name, :args, :whereparams, :body])
            @test d[:whereparams] == [:A, :(B <: A)]

            c_expr = combinedef(d)
            expr = @expr f(::A, ::B) where {A, B <: A} = nothing
            expr.head = short ? :(=) : :function
            @test strip_lineno!(c_expr) == strip_lineno!(expr)
        end
    end

    @testset "where ($(function_form(short)) anonymous function)" for short in (true, false)
        @testset "where" begin
            f, expr = if short
                @audit ((::A) where A) -> nothing
            else
                @audit function (::A) where A; nothing end
            end
            @test length(methods(f)) == 1

            d = splitdef(expr)
            @test keys(d) == Set([:head, :args, :whereparams, :body])
            @test d[:whereparams] == [:A]

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "curly where" begin
            f, expr = if short
                @audit ((::A, ::B) where {A, B <: A}) -> nothing
            else
                @audit function (::A, ::B) where {A, B <: A}; nothing end
            end
            @test length(methods(f)) == 1

            d = splitdef(expr)
            @test keys(d) == Set([:head, :args, :whereparams, :body])
            @test d[:whereparams] == [:A, :(B <: A)]

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "multiple where" begin
            f, expr = if short
                @audit ((::A, ::B) where B <: A where A) -> nothing
            else
                @audit function (::A, ::B) where B <: A where A; nothing end
            end
            @test length(methods(f)) == 1

            d = splitdef(expr)
            @test keys(d) == Set([:head, :args, :whereparams, :body])
            @test d[:whereparams] == [:A, :(B <: A)]

            c_expr = combinedef(d)
            expr = @expr ((::A, ::B) where {A, B <: A}) -> nothing
            expr.head = short ? :-> : :function
            @test strip_lineno!(c_expr) == strip_lineno!(expr)
        end
    end

    @testset "return-type ($(function_form(short)) function)" for short in (true, false)
        @testset "f(x)::Integer" begin
            f, expr = if short
                @audit f(x)::Integer = x
            else
                @audit function f(x)::Integer; x end
            end
            @test length(methods(f)) == 1
            @test f(0.0) isa Integer

            d = splitdef(expr)
            @test keys(d) == Set([:head, :name, :args, :rtype, :body])
            @test d[:rtype] == :Integer

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "(f(x::T)::Integer) where T" begin
            f, expr = if short
                @audit (f(x::T)::Integer) where T = x
            else
                @audit function (f(x::T)::Integer) where T; x end
            end
            @test length(methods(f)) == 1
            @test f(0.0) isa Integer

            d = splitdef(expr)
            @test keys(d) == Set([:head, :name, :args, :rtype, :whereparams, :body])
            @test d[:rtype] == :Integer

            c_expr = combinedef(d)
            @test c_expr == expr
        end
    end

    @testset "return-type (short-form anonymous function)" begin
        @testset "(x,)::Integer" begin
            f, expr = @audit (x,)::Integer -> x  # Interpreted as `(x::Integer,) -> x`
            @test length(methods(f)) == 1
            @test f(0) == 0
            @test_throws MethodError f(0.0)

            d = splitdef(expr)
            @test keys(d) == Set([:head, :args, :body])
            @test d[:args] == [:((x,)::Integer)]

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "(((x::T,)::Integer) where T)" begin
            f, expr = @audit (((x::T,)::Integer) where T) -> x
            @test f isa ErrorException

            @test_broken splitdef(expr, throw=false) === nothing

            d = Dict(
                :head => :(->),
                :args => [:(x::T)],
                :rtype => :Integer,
                :whereparams => [:T],
                :body => quote
                    x
                end
            )
            c_expr = combinedef(d)
            expr = @expr (((x::T)::Integer) where T) -> x
            @test strip_lineno!(c_expr) == strip_lineno!(expr)
        end
    end

    @testset "return-type (long-form anonymous function)" begin
        @testset "(x)::Integer" begin
            # Interpreted as `function (x::Integer); x end`
            f, expr = @audit function (x)::Integer; x end
            @test length(methods(f)) == 1
            @test f(0) == 0
            @test_throws MethodError f(0.0)

            d = splitdef(expr)
            @test keys(d) == Set([:head, :args, :body])
            @test d[:args] == [:(x::Integer)]

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "(((x::T)::Integer) where T)" begin
            expr = Expr(:function,
                Expr(:where, Expr(:(::), Expr(:tuple, :(x::T)), :Integer), :T),
                Expr(:block, :x),
            )
            @test_throws ErrorException eval(expr)

            @test_broken splitdef(expr, throw=false) === nothing

            d = Dict(
                :head => :function,
                :args => [:(x::T)],
                :rtype => :Integer,
                :whereparams => [:T],
                :body => quote
                    x
                end
            )
            c_expr = combinedef(d)
            @test strip_lineno!(c_expr) == strip_lineno!(expr)
        end
    end

    @testset "invalid definitions" begin
        # Invalid function type
        @test_splitdef_invalid Expr(:block)

        # Too few expression arguments
        @test_splitdef_invalid Expr(:function)
        @test_splitdef_invalid Expr(:(=), :f)

        # Too many expression arguments
        @test_splitdef_invalid Expr(:function, :f, :x, :y)
        @test_splitdef_invalid Expr(:(=), :f, :x, :y)

        # Invalid or missing arguments
        @test_splitdef_invalid :(f{S} = 0)
        @test_broken splitdef(:(a::Number::Int -> a); throws=false) === nothing

        # Invalid argument block expression
        ex = :((x; y; z) -> 0)  # Note: inlining this strips LineNumberNodes from the block
        @test any(arg -> arg isa LineNumberNode, ex.args[1].args)
        @test_splitdef_invalid ex
        @test_splitdef_invalid Expr(:->, Expr(:block, :x, :y, :z), Expr(:block, 0))

        # Empty function contains extras
        @test_throws ArgumentError combinedef(Dict(:head => :function, :name => :f, :args => []))
    end
end
