"""
    signature(meth::Method) -> Dict{Symbol,Any}

Finds the expression for a methods signature as broken up into its various components
including:

- `:name`: Name of the function
- `:params`: Parametric types defined on constructors
- `:args`: Positional arguments of the function
- `:whereparams`: Where parameters

All components listed above may not be present in the returned dictionary

Right now the following components will never be returned:
 - `:kwargs`: Keyword arguments of the function
 - `:rtype`: Return type of the function
 - `:body`: Function body

These are the same components returned by [`splitdef`](@ref) and required by
[`combinedef`](@red), except for the `:body` component which will never be present.
"""
function signature(meth::Method)
    def = Dict{Symbol,Any}()
    def[:name] = meth.name

    def[:args] = arguments(meth)
    def[:whereparams] = where_parameters(meth)

    return Dict(k=>v for (k, v) in def if v !== nothing)  # filter out nonfields.
end

function slot_names(meth::Method)
    ci = Base.uncompressed_ast(meth)
    return ci.slotnames
end

function argument_names(meth::Method)
    slot_syms = slot_names(meth)
    @assert slot_syms[1] === Symbol("#self#")
    arg_names = slot_syms[2:meth.nargs]  # nargs includes 1 for `#self#`
    return arg_names
end


function argument_types(meth::Method)
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
    whereparam = where_parameters(x.var)
    return :($name where $whereparam)
end


function arguments(meth::Method)
    arg_names = argument_names(meth)
    arg_types = argument_types(meth)
    map(arg_names, arg_types) do name, type
        has_name = name !== Symbol("#unused#")
        type_name = name_of_arg_type(type)
        if type === Any && has_name
            name
        elseif has_name
            :($name::$type_name)
        else
            :(::$type_name)
        end
    end
end

function where_parameters(x::TypeVar)
    if x.lb === Union{} && x.ub === Any
        return x.name
    elseif x.lb === Union{}
        return :($(x.name) <: $(Symbol(x.ub)))
    elseif x.ub === Any
        return :($(x.name) >: $(Symbol(x.lb)))
    else
        return :($(Symbol(x.lb)) <: $(x.name) <: $(Symbol(x.ub)))
    end
end

function where_parameters(meth::Method)
    meth.sig isa UnionAll || return nothing

    whereparams = []
    sig = meth.sig
    while sig isa UnionAll
        push!(whereparams, where_parameters(sig.var))
        sig = sig.body
    end
    return whereparams
end
