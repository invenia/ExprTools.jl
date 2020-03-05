"""
    signature(meth::Method) -> Dict{Symbol,Any}

Finds the expression for a methods signature as broken up into its various components
including:

- `:head`: Expression head of the function definition: always `:function`
- `:name`: Name of the function (not present for anonymous functions)
- `:params`: Parametric types defined on constructors
- `:args`: Positional arguments of the function
- `:kwargs`: Keyword arguments of the function
- `:rtype`: Return type of the function
- `:whereparams`: Where parameters

All components listed may not be present in the returned dictionary with the exception of
`:head` which will always be present.

These are the same components returned by [`splitdef`](@ref) and consumed by
[`combinedef`](@red), except for the `:body` component which will never be present.
"""
function signature(meth::Method)
    def = Dict{Symbol,Any}()
    def[:head] = :function
    def[:name] = meth.name


    def[:args] = get_args(meth)
    def[:whereparams] = get_whereparams(meth)

    return Dict(k=>v for (k, v) in def if !isnothing(v))  # filter out nonfields.
end

get_slot_sym(meth::Method) = Symbol.(split(meth.slot_syms, '\0'; keepempty=false))

function get_arg_names(meth::Method)
    slot_syms = get_slot_sym(meth)
    @assert slot_syms[1] == Symbol("#self#")
    arg_names = slot_syms[2:meth.nargs]  #nargs includes 1 for #self#
    return arg_names
end

"""
    parameters(type)

extracts the type-parameters of the `type`.
E.g. `parameters(Foo{A, B, C}) == [A, B, C]`
"""
parameters(sig::UnionAll) = parameters(sig.body)
parameters(sig::DataType) = sig.parameters

function get_arg_types(meth::Method)
    # First parameter of `sig` is the type of the function itself
    return parameters(meth.sig)[2:end]
end

name_of_arg_type(x) = x
name_of_arg_type(tv::TypeVar) = tv.name
function name_of_arg_type(x::DataType)
    name_sym = Symbol(x.name)
    if isempty(x.parameters)
        return name_sym
    else
        parameter_names = name_of_arg_type.(x.parameters)
        return :($(name_sym){$(parameter_names...)})
    end
end
function name_of_arg_type(x::UnionAll)
    name = name_of_arg_type(x.body)
    whereparam = get_whereparam(x.var)
    return :($name where $whereparam)
end



function get_args(meth::Method)
    arg_names = get_arg_names(meth)
    arg_types = get_arg_types(meth)
    map(arg_names, arg_types) do name, type
        if type === Any
            name
        else
            :($name::$(name_of_arg_type(type)))
        end
    end
end

function get_whereparam(x::TypeVar)
    if x.lb === Union{} && x.ub === Any
        return x.name
    elseif x.lb === Union{}
        return :($(x.name) <: $(Symbol(x.ub)))
    elseif x.ub === Any
        return :($(x.name) >: $(Symbol(x.lb)))
    else
        return :($(Symbol(x.lb)) <: $(x.name) <: $(Symbol(x.ub)))
    end
    # TODO other bounds
end

function get_whereparams(meth::Method)
    meth.sig isa UnionAll || return nothing

    whereparams = []
    sig = meth.sig
    while sig isa UnionAll
        push!(whereparams, get_whereparam(sig.var))
        sig = sig.body
    end
    return whereparams
end
