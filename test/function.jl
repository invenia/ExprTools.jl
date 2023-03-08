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
anon_assigned(isassigned::Bool) = isassigned ? "assigned " : ""

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

    @testset "$(anon_assigned(ia))long-form anonymous function" for ia in (true, false)
        f, expr = if ia
            @audit f = function () end
        else
            @audit function () end
        end
        @test length(methods(f)) == 1
        @test f() === nothing

        d = splitdef(expr)
        if ia
            @test keys(d) == Set([:head, :body, :name, :anonhead])
            @test d[:head] == :(=)
            @test d[:anonhead] == :function
            @test d[:name] == :f
        else 
            @test keys(d) == Set([:head, :body])
            @test d[:head] == :function
        end
        @test strip_lineno!(d[:body]) == Expr(:block)

        c_expr = combinedef(d)
        @test c_expr == expr
    end

    @testset "$(anon_assigned(ia))short-form anonymous function" for ia in (true, false)
        f, expr = if ia
            @audit f = () -> nothing
        else
            @audit () -> nothing
        end

        @test length(methods(f)) == 1
        @test f() === nothing

        d = splitdef(expr)
        if ia
            @test keys(d) == Set([:head, :body, :name, :anonhead])
            @test d[:head] == :(=)
            @test d[:anonhead] == :(->)
            @test d[:name] == :f
        else 
            @test keys(d) == Set([:head, :body])
            @test d[:head] == :(->)
        end
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

    @testset "args ($(anon_assigned(ia))$(function_form(short)) anonymous function)" for ia in (true, false), short in (true, false)
        @testset "x" begin
            f, expr = if short
                if ia
                    @audit f = x -> x
                else
                    @audit x -> x
                end
            else
                if ia
                    @audit f = function (x) x end
                else
                    @audit function (x) x end
                end
            end
            @test length(methods(f)) == 1
            @test f(0) == 0

            d = splitdef(expr)
            if ia
                @test keys(d) == Set([:head, :args, :body, :name, :anonhead])
            else
                @test keys(d) == Set([:head, :args, :body])
            end
            @test d[:args] == [:x]

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "x::Integer" begin
            f, expr = if short
                if ia
                    @audit f = x::Integer -> x
                else
                    @audit x::Integer -> x
                end
            else
                if ia
                    @audit f = function (x::Integer) x end
                else
                   @audit function (x::Integer) x end
                end
            end
            @test length(methods(f)) == 1
            @test f(0) == 0

            d = splitdef(expr)
            if ia
                @test keys(d) == Set([:head, :args, :body, :name, :anonhead])
            else
                @test keys(d) == Set([:head, :args, :body])
            end
            @test d[:args] == [:(x::Integer)]

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "(x=1)" begin
            f, expr = if short
                if ia
                    @audit f = (x=1) -> x
                else
                    @audit (x=1) -> x
                end
            else
                if ia
                    @audit f = function (x=1) x end
                else
                   @audit function (x=1) x end
                end
            end
            @test length(methods(f)) == 2
            @test f(0) == 0
            @test f() == 1

            d = splitdef(expr)
            if ia
                @test keys(d) == Set([:head, :args, :body, :name, :anonhead])
            else
                @test keys(d) == Set([:head, :args, :body])
            end
            @test d[:args] == [:(x=1)]

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "(x::Integer=1)" begin
            f, expr = if short
                if ia
                    @audit f = (x::Integer=1) -> x
                else
                    @audit (x::Integer=1) -> x
                end
            else
                if ia
                    @audit f = function (x::Integer=1) x end
                else
                   @audit function (x::Integer=1) x end
                end
            end
            @test length(methods(f)) == 2
            @test f(0) == 0
            @test f() == 1

            d = splitdef(expr)
            if ia
                @test keys(d) == Set([:head, :args, :body, :name, :anonhead])
            else
                @test keys(d) == Set([:head, :args, :body])
            end
            @test d[:args] == [:(x::Integer=1)]

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "(x,)" begin
            f, expr = if short
                if ia
                    @audit f = (x,) -> x
                else
                    @audit (x,) -> x
                end
            else
                if ia
                    @audit f = function (x,) x end
                else
                   @audit function (x,) x end
                end
            end
            @test length(methods(f)) == 1
            @test f(0) == 0

            d = splitdef(expr)
            if ia
                @test keys(d) == Set([:head, :args, :body, :name, :anonhead])
            else
                @test keys(d) == Set([:head, :args, :body])
            end
            @test d[:args] == [:x]

            c_expr = combinedef(d)
            expr = short ? ia ? (@expr f = x -> x) : (@expr x -> x) : ia ? (@expr f = function (x) x end) : (@expr function (x) x end)
            @test strip_lineno!(c_expr) == strip_lineno!(expr)
        end

        @testset "(x::Integer,)" begin
            f, expr = if short
                if ia
                    @audit f = (x::Integer,) -> x
                else
                    @audit (x::Integer,) -> x
                end
            else
                if ia
                    @audit f = function (x::Integer,) x end
                else
                   @audit function (x::Integer,) x end
                end
            end
            @test length(methods(f)) == 1
            @test f(0) == 0

            d = splitdef(expr)
            if ia
                @test keys(d) == Set([:head, :args, :body, :name, :anonhead])
            else
                @test keys(d) == Set([:head, :args, :body])
            end
            @test d[:args] == [:(x::Integer)]

            c_expr = combinedef(d)
            expr = short ? ia ? (@expr f = (x::Integer) -> x) : (@expr (x::Integer) -> x) : ia ? (@expr f = function (x::Integer) x end) : (@expr function (x::Integer) x end)
            @test strip_lineno!(c_expr) == strip_lineno!(expr)
        end

        @testset "(x=1,)" begin
            f, expr = if short
                if ia
                    @audit f = (x=1,) -> x
                else
                    @audit (x=1,) -> x
                end
            else
                if ia
                    @audit f = function (x=1,) x end
                else
                   @audit function (x=1,) x end
                end
            end
            @test length(methods(f)) == 2
            @test f(0) === 0
            @test f() === 1

            d = splitdef(expr)
            if ia
                @test keys(d) == Set([:head, :args, :body, :name, :anonhead])
            else
                @test keys(d) == Set([:head, :args, :body])
            end
            @test d[:args] == [:(x=1)]

            c_expr = combinedef(d)
            expr = short ? ia ? (@expr f = (x=1) -> x) : (@expr (x=1) -> x) : ia ? (@expr f = function (x=1) x end) : (@expr function (x=1) x end)
            @test strip_lineno!(c_expr) == strip_lineno!(expr)
        end

        @testset "(x::Integer=1,)" begin
            f, expr = if short
                if ia
                    @audit f = (x::Integer=1,) -> x
                else
                    @audit (x::Integer=1,) -> x
                end
            else
                if ia
                    @audit f = function (x::Integer=1,) x end
                else
                   @audit function (x::Integer=1,) x end
                end
            end
            @test length(methods(f)) == 2
            @test f(0) == 0
            @test f() == 1

            d = splitdef(expr)
            if ia
                @test keys(d) == Set([:head, :args, :body, :name, :anonhead])
            else
                @test keys(d) == Set([:head, :args, :body])
            end            
            @test d[:args] == [:(x::Integer=1)]

            c_expr = combinedef(d)
            expr = short ? ia ? (@expr f = (x::Integer=1) -> x) : (@expr (x::Integer=1) -> x) : ia ? (@expr f = function (x::Integer=1) x end) : (@expr function (x::Integer=1) x end)
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

    @testset "kwargs ($(anon_assigned(ia))$(function_form(short)) function)" for ia in (true, false), short in (true, false)
        @testset "(; x)" begin
            f, expr = if short
                if ia
                    @audit f = (; x) -> x
                else
                    @audit (; x) -> x
                end
            else
                if ia
                    @audit f = function (; x) x end
                else
                   @audit function (; x) x end
                end
            end
            @test length(methods(f)) == 1
            @test f(x=0) == 0

            d = splitdef(expr)
            if ia
                @test keys(d) == Set([:head, :kwargs, :body, :name, :anonhead])
            else
                @test keys(d) == Set([:head, :kwargs, :body])
            end
            @test d[:kwargs] == [:x]

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "(; x::Integer)" begin
            f, expr = if short
                if ia
                    @audit f = (; x::Integer) -> x
                else
                    @audit (; x::Integer) -> x
                end
            else
                if ia
                    @audit f = function (; x::Integer) x end
                else
                   @audit function (; x::Integer) x end
                end
            end
            @test length(methods(f)) == 1
            @test f(x=0) == 0

            d = splitdef(expr)
            if ia
                @test keys(d) == Set([:head, :kwargs, :body, :name, :anonhead])
            else
                @test keys(d) == Set([:head, :kwargs, :body])
            end
            @test d[:kwargs] == [:(x::Integer)]

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "(; x=1)" begin
            f, expr = if short
                if ia
                    @audit f = (; x=1) -> x
                else
                    @audit (; x=1) -> x
                end
            else
                if ia
                    @audit f = function (; x=1) x end
                else
                   @audit function (; x=1) x end
                end
            end
            @test length(methods(f)) == 1
            @test f(x=0) == 0

            d = splitdef(expr)
            if ia
                @test keys(d) == Set([:head, :kwargs, :body, :name, :anonhead])
            else
                @test keys(d) == Set([:head, :kwargs, :body])
            end
            @test d[:kwargs] == [Expr(:kw, :x, 1)]

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "(; x::Integer=1)" begin
            f, expr = if short
                if ia
                    @audit f = (; x::Integer=1) -> x
                else
                    @audit (; x::Integer=1) -> x
                end
            else
                if ia
                    @audit f = function (; x::Integer=1) x end
                else
                   @audit function (; x::Integer=1) x end
                end
            end
            @test length(methods(f)) == 1
            @test f(x=0) == 0

            d = splitdef(expr)
            if ia
                @test keys(d) == Set([:head, :kwargs, :body, :name, :anonhead])
            else
                @test keys(d) == Set([:head, :kwargs, :body])
            end
            @test d[:kwargs] == [Expr(:kw, :(x::Integer), 1)]

            c_expr = combinedef(d)
            @test c_expr == expr
        end
    end

    # When using :-> there are a few definitions that use a block expression instead of the
    # typical tuple.
    @testset "block expression ($(anon_assigned(ia))$(function_form(short)) anonymous function)" for ia in (true, false), short in (true, false)
        @testset "(;)" begin
            # The `(;)` syntax was deprecated in 1.4.0-DEV.585 (ce29ec547e) but we can still
            # test the behavior with `begin end`.
            f, expr = if short
                if ia
                    @audit f = (begin end) -> nothing
                else
                    @audit (begin end) -> nothing
                end
            else
                if ia
                    @audit f = function (begin end) nothing end
                else
                   @audit function (begin end) nothing end
                end
            end
            @test length(methods(f)) == 1
            @test f() === nothing

            # Note: the semi-colon is missing from the expression
            d = splitdef(expr)
            if ia
                @test keys(d) == Set([:head, :kwargs, :body, :name, :anonhead])
            else
                @test keys(d) == Set([:head, :kwargs, :body])
            end
            @test d[:kwargs] == []

            c_expr = combinedef(d)
            expr = Expr(:->, Expr(:tuple, Expr(:parameters)), Expr(:block, :nothing))
            expr.head = short ? :-> : :function
            if ia
                expr = Expr(:(=), :f, expr)
            end
            @test strip_lineno!(c_expr) == strip_lineno!(expr)
        end

        @testset "(x;)" begin
            f, expr = if short
                if ia
                    @audit f = (x;) -> x
                else
                    @audit (x;) -> x
                end
            else
                if ia
                    @audit f = function (x;) x end
                else
                   @audit function (x;) x end
                end
            end
            @test length(methods(f)) == 1
            @test f(0) == 0

            # Note: the semi-colon is missing from the expression
            d = splitdef(expr)
            if ia
                @test keys(d) == Set([:head, :args, :kwargs, :body, :name, :anonhead])
            else
                @test keys(d) == Set([:head, :args, :kwargs, :body])
            end
            @test d[:args] == [:x]
            @test d[:kwargs] == []

            c_expr = combinedef(d)
            expr = Expr(:->, Expr(:tuple, Expr(:parameters), :x), Expr(:block, :x))
            expr.head = short ? :-> : :function
            if ia
                expr = Expr(:(=), :f, expr)
            end
            @test strip_lineno!(c_expr) == strip_lineno!(expr)
        end

        @testset "(x; y)" begin
            f, expr = if short
                if ia
                    @audit f = (x; y) -> (x, y)
                else
                    @audit (x; y) -> (x, y)
                end
            else
                if ia
                    @audit f = function (x; y); (x, y) end
                else
                   @audit function (x; y); (x, y) end
                end
            end
            @test length(methods(f)) == 1
            @test f(0, y=1) == (0, 1)

            # Note: the semi-colon is missing from the expression
            d = splitdef(expr)
            if ia
                @test keys(d) == Set([:head, :args, :kwargs, :body, :name, :anonhead])
            else
                @test keys(d) == Set([:head, :args, :kwargs, :body])
            end
            @test d[:args] == [:x]
            @test d[:kwargs] == [:y]

            c_expr = combinedef(d)
            expr = Expr(:->, Expr(:tuple, Expr(:parameters, :y), :x), Expr(:block, :((x, y))))
            expr.head = short ? :-> : :function
            if ia
                expr = Expr(:(=), :f, expr)
            end
            @test strip_lineno!(c_expr) == strip_lineno!(expr)
        end

        @testset "(x; y = 0)" begin
            f, expr = if short
                if ia
                    @audit f = (x; y = 0) -> (x, y)
                else
                    @audit (x; y = 0) -> (x, y)
                end
            else
                if ia
                    @audit f = function (x; y = 0); (x, y) end
                else
                   @audit function (x; y = 0); (x, y) end
                end
            end
            @test length(methods(f)) == 1
            @test f(0) == (0, 0)
            @test f(0, y=1) == (0, 1)

            # Note: the semi-colon is missing from the expression
            d = splitdef(expr)
            if ia
                @test keys(d) == Set([:head, :args, :kwargs, :body, :name, :anonhead])
            else
                @test keys(d) == Set([:head, :args, :kwargs, :body])
            end
            @test d[:args] == [:x]
            @test d[:kwargs] == [Expr(:kw, :y, 0)]

            c_expr = combinedef(d)
            expr = Expr(:->, Expr(:tuple, Expr(:parameters, Expr(:kw, :y, 0)), :x), Expr(:block, :((x, y))))
            expr.head = short ? :-> : :function
            if ia
                expr = Expr(:(=), :f, expr)
            end
            @test strip_lineno!(c_expr) == strip_lineno!(expr)
        end

        @testset "(x; y = 0, _...)" begin
            f, expr = if short
                if ia
                    @audit f = (x; y = 0, _...) -> (x, y)
                else
                    @audit (x; y = 0, _...) -> (x, y)
                end
            else
                if ia
                    @audit f = function (x; y = 0, _...); (x, y) end
                else
                   @audit function (x; y = 0, _...); (x, y) end
                end
            end
            @test length(methods(f)) == 1
            @test f(0) == (0, 0)
            @test f(0, y=1) == (0, 1)
            @test f(0, y=1, z=2) == (0, 1)

            # Note: the semi-colon is missing from the expression
            d = splitdef(expr)
            if ia
                @test keys(d) == Set([:head, :args, :kwargs, :body, :name, :anonhead])
            else
                @test keys(d) == Set([:head, :args, :kwargs, :body])
            end
            @test d[:args] == [:x]
            @test d[:kwargs] == [Expr(:kw, :y, 0), :(_...)]

            c_expr = combinedef(d)
            expr = Expr(:->, Expr(:tuple, Expr(:parameters, Expr(:kw, :y, 0), :(_...)), :x), Expr(:block, :((x, y))))
            expr.head = short ? :-> : :function
            if ia
                expr = Expr(:(=), :f, expr)
            end
            @test strip_lineno!(c_expr) == strip_lineno!(expr)
        end

        @testset "Expr(:block, :x, :y)" begin
            expr = Expr(:->, Expr(:block, :x, :y), Expr(:block, :((x, y))))
            expr.head = short ? :-> : :function
            if ia
                expr = Expr(:(=), :f, expr)
            end
            f = @eval $expr
            @test length(methods(f)) == 1
            @test f(0, y=1) == (0, 1)

            # Note: the semi-colon is missing from the expression
            d = splitdef(expr)
            if ia
                @test keys(d) == Set([:head, :args, :kwargs, :body, :name, :anonhead])
            else
                @test keys(d) == Set([:head, :args, :kwargs, :body])
            end
            @test d[:args] == [:x]
            @test d[:kwargs] == [:y]

            c_expr = combinedef(d)
            expr = Expr(:->, Expr(:tuple, Expr(:parameters, :y), :x), Expr(:block, :((x, y))))
            expr.head = short ? :-> : :function
            if ia
                expr = Expr(:(=), :f, expr)
            end
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

    @testset "where ($(anon_assigned(ia))$(function_form(short)) anonymous function)" for ia in (true, false), short in (true, false)
        @testset "where" begin
            f, expr = if short
                if ia
                    @audit f = ((::A) where A) -> nothing
                else
                    @audit ((::A) where A) -> nothing
                end
            else
                if ia
                    @audit f = function (::A) where A; nothing end
                else
                   @audit function (::A) where A; nothing end
                end
            end
            @test length(methods(f)) == 1

            d = splitdef(expr)
            if ia
                @test keys(d) == Set([:head, :args, :whereparams, :body, :name, :anonhead])
            else
                @test keys(d) == Set([:head, :args, :whereparams, :body])
            end
            @test d[:whereparams] == [:A]

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "curly where" begin
            f, expr = if short
                if ia
                    @audit f = ((::A, ::B) where {A, B <: A}) -> nothing
                else
                    @audit ((::A, ::B) where {A, B <: A}) -> nothing
                end
            else
                if ia
                    @audit f = function (::A, ::B) where {A, B <: A}; nothing end
                else
                   @audit function (::A, ::B) where {A, B <: A}; nothing end
                end
            end
            @test length(methods(f)) == 1

            d = splitdef(expr)
            if ia
                @test keys(d) == Set([:head, :args, :whereparams, :body, :name, :anonhead])
            else
                @test keys(d) == Set([:head, :args, :whereparams, :body])
            end
            @test d[:whereparams] == [:A, :(B <: A)]

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "multiple where" begin
            f, expr = if short
                if ia
                    @audit f = ((::A, ::B) where B <: A where A) -> nothing
                else
                    @audit ((::A, ::B) where B <: A where A) -> nothing
                end
            else
                if ia
                    @audit f = function (::A, ::B) where B <: A where A; nothing end
                else
                   @audit function (::A, ::B) where B <: A where A; nothing end
                end
            end
            @test length(methods(f)) == 1

            d = splitdef(expr)
            if ia
                @test keys(d) == Set([:head, :args, :whereparams, :body, :name, :anonhead])
            else
                @test keys(d) == Set([:head, :args, :whereparams, :body])
            end
            @test d[:whereparams] == [:A, :(B <: A)]

            c_expr = combinedef(d)
            expr = @expr ((::A, ::B) where {A, B <: A}) -> nothing
            expr.head = short ? :-> : :function
            if ia
                expr = Expr(:(=), :f, expr)
            end
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

    @testset "return-type ($(anon_assigned(ia))short-form anonymous function)" for ia in (true, false)
        @testset "(x,)::Integer" begin
            f, expr = if ia
                @audit f = (x,)::Integer -> x
            else
                @audit (x,)::Integer -> x  # Interpreted as `(x::Integer,) -> x`
            end
            @test length(methods(f)) == 1
            @test f(0) == 0
            @test_throws MethodError f(0.0)

            d = splitdef(expr)
            if ia
                @test keys(d) == Set([:head, :args, :body, :name, :anonhead])
            else
                @test keys(d) == Set([:head, :args, :body])
            end
            @test d[:args] == [:((x,)::Integer)]

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "(((x::T,)::Integer) where T)" begin
            f, expr = if ia
                @audit f = (((x::T,)::Integer) where T) -> x
            else
                @audit (((x::T,)::Integer) where T) -> x
            end
            @test f isa ErrorException

            @test_broken splitdef(expr, throw=false) === nothing

            if ia
                d = Dict(
                    :head => :(=),
                    :name => :f,
                    :anonhead => :(->),
                    :args => [:(x::T)],
                    :rtype => :Integer,
                    :whereparams => [:T],
                    :body => quote
                        x
                    end
                )
            else
                d = Dict(
                    :head => :(->),
                    :args => [:(x::T)],
                    :rtype => :Integer,
                    :whereparams => [:T],
                    :body => quote
                        x
                    end
                )
            end
            c_expr = combinedef(d)
            expr = if ia
                @expr f = (((x::T)::Integer) where T) -> x
            else
                @expr (((x::T)::Integer) where T) -> x
            end
            @test strip_lineno!(c_expr) == strip_lineno!(expr)
        end
    end

    @testset "return-type ($(anon_assigned(ia))long-form anonymous function)" for ia in (true, false)
        @testset "(x)::Integer" begin
            # Interpreted as `function (x::Integer); x end`
            f, expr = if ia
                @audit f = function (x)::Integer; x end
            else
                @audit function (x)::Integer; x end
            end
            @test length(methods(f)) == 1
            @test f(0) == 0
            @test_throws MethodError f(0.0)

            d = splitdef(expr)
            if ia
                @test keys(d) == Set([:head, :args, :body, :name, :anonhead])
            else
                @test keys(d) == Set([:head, :args, :body])
            end
            @test d[:args] == [:(x::Integer)]

            c_expr = combinedef(d)
            @test c_expr == expr
        end

        @testset "(((x::T)::Integer) where T)" begin
            expr = Expr(:function,
                Expr(:where, Expr(:(::), Expr(:tuple, :(x::T)), :Integer), :T),
                Expr(:block, :x),
            )
            if ia
                expr = Expr(:(=), :f, expr)
            end
            @test_throws ErrorException eval(expr)

            @test_broken splitdef(expr, throw=false) === nothing

            if ia
                d = Dict(
                    :head => :(=),
                    :name => :f,
                    :anonhead => :function,
                    :args => [:(x::T)],
                    :rtype => :Integer,
                    :whereparams => [:T],
                    :body => quote
                        x
                    end
                )
            else
                d = Dict(
                    :head => :function,
                    :args => [:(x::T)],
                    :rtype => :Integer,
                    :whereparams => [:T],
                    :body => quote
                        x
                    end
                )
            end
            c_expr = combinedef(d)
            @test strip_lineno!(c_expr) == strip_lineno!(expr)
        end
    end

    @testset "combinedef with no `:head`" begin
        # should default to `:function`
        f, expr = @audit function f() end

        d = splitdef(expr)
        delete!(d, :head)
        @assert !haskey(d, :head)

        c_expr = combinedef(d)
        @test c_expr == expr
    end

    @testset "invalid definitions" begin
        # Invalid function type
        @test_splitdef_invalid Expr(:block)

        # Too few expression arguments
        @test_splitdef_invalid Expr(:function)
        @test_splitdef_invalid Expr(:(=), :f)
        @test_splitdef_invalid Expr(:function, :(f(x)))

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
