# These utilities are for working with the signature_def `Dict` that comes out of
# `signature`/`splitdef`



"""
    args_tuple_expr(signature_def::Dict{Symbol})
    args_tuple_expr(arg_exprs)

For `arg_exprs` being a list of positional argument expressions from a signature, of a form
such as `[:(x::Int), :(y::Float64), :(z::Vararg)]`, or being a whole `signature_def` `Dict`
containing a `signature_def[:args]` value of that form.

This returns a tuple expression containing all of the args by name. It correctly handles
splatting for things that are `Vararg` typed, e.g for the prior example `:((x, y, z...))`

This is useful for modifying the `signature_def[:body]`.
For example, one could printout all the arguments via

```julia
signature_def[:body] = quote
    args = \$(args_tuple_expr(signature_def))
    println("args = ",args)
    \$(signature_def[:body]) # insert old body
end
```

A more realistic use case is if you want to insert a call to another function
that accepts the same arguments as the original function.
"""
function args_tuple_expr end

args_tuple_expr(signature_def::Dict{Symbol}) = args_tuple_expr(signature_def[:args])

function args_tuple_expr(arg_exprs)
    ret = Expr(:tuple)
    ret.args = map(arg_exprs) do arg

        # remove splatting (will put back on at end)
        was_splatted = Meta.isexpr(arg, :(...), 1)
        if was_splatted
            arg = arg.args[1]
        end

        # handle presence or absence of type constraints
        if Meta.isexpr(arg, :(::), 2)
            arg_name, Texpr = arg.args
        elseif arg isa Symbol
            arg_name = arg
            Texpr = nothing
        else
            error("unexpected form of argument: $arg")
        end

        # Clean up types so we can recognise if it is `Vararg`
        # remove where clauses (because they interfere with recognizing Vararg)
        if Meta.isexpr(Texpr, :where)
            Texpr = Texpr.args[1]
        end
        # remove curlies from type constraints Needs to be after removing `where`
        # important because we want to make Vararg{T,N}` into just `Vararg`
        if Meta.isexpr(Texpr, :curly)
            Texpr = Texpr.args[1]
        end
        # now can detect if should be splatted because of using Vararg in some form
        was_splatted |= Texpr == :Vararg

        #Finally apply splatting if required.
        if was_splatted
            return :($arg_name...)
        else
            return arg_name
        end
    end
    return ret
end
