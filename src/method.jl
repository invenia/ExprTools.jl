"""
    signature(m::Method) -> Dict{Symbol,Any}

Finds the expression for a method's signature as broken up into its various components
including:

- `:name`: Name of the function
- `:params`: Parametric types defined on constructors
- `:args`: Positional arguments of the function
- `:whereparams`: Where parameters

All components listed above may not be present in the returned dictionary if they are
not in the function definition.

Limited support for:
- `:kwargs`: Keyword arguments of the function.
  Only the names will be included, not the default values or type constraints.

Unsupported:
- `:rtype`: Return type of the function
- `:body`: Function body0
- `:head`: Expression head of the function definition (`:function`, `:(=)`, `:(->)`)

For more complete coverage, consider using [`splitdef`](@ref)
with [`CodeTracking.definition`](https://github.com/timholy/CodeTracking.jl).

The dictionary of components returned by `signature` match those returned by
[`splitdef`](@ref) and include all that are required by [`combinedef`](@ref), except for
the `:body` component.
"""
function signature(m::Method)
    def = Dict{Symbol, Any}()
    def[:name] = m.name

    def[:args] = arguments(m)
    def[:whereparams] = where_parameters(m)
    def[:params] = type_parameters(m)
    def[:kwargs] = kwargs(m)

    return Dict(k => v for (k, v) in def if v !== nothing)  # filter out nonfields.
end

function slot_names(m::Method)
    ci = Base.uncompressed_ast(m)
    return ci.slotnames
end

function argument_names(m::Method)
    slot_syms = slot_names(m)
    @assert slot_syms[1] === Symbol("#self#")
    arg_names = slot_syms[2:m.nargs]  # nargs includes 1 for `#self#`
    return arg_names
end

argument_types(m::Method) = argument_types(m.sig)
function argument_types(sig)
    # First parameter of `sig` is the type of the function itself
    return parameters(sig)[2:end]
end

name_of_type(x) = x
name_of_type(tv::TypeVar) = tv.name
function name_of_type(x::DataType)
    name_sym = Symbol(x.name)
    if isempty(x.parameters)
        return name_sym
    else
        parameter_names = name_of_type.(x.parameters)
        return :($(name_sym){$(parameter_names...)})
    end
end
function name_of_type(x::UnionAll)
    name = name_of_type(x.body)
    whereparam = where_parameters(x.var)
    return :($name where $whereparam)
end
function name_of_type(x::Union)
    parameter_names = name_of_type.(Base.uniontypes(x))
    return :(Union{$(parameter_names...)})
end

function arguments(m::Method)
    arg_names = argument_names(m)
    arg_types = argument_types(m)
    map(arg_names, arg_types) do name, type
        has_name = name !== Symbol("#unused#")
        type_name = name_of_type(type)
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
        return :($(x.name) <: $(name_of_type(x.ub)))
    elseif x.ub === Any
        return :($(x.name) >: $(name_of_type(x.lb)))
    else
        return :($(name_of_type(x.lb)) <: $(x.name) <: $(name_of_type(x.ub)))
    end
end

where_parameters(m::Method) = where_parameters(m.sig)
where_parameters(sig) = nothing
function where_parameters(sig::UnionAll)
    whereparams = []
    while sig isa UnionAll
        push!(whereparams, where_parameters(sig.var))
        sig = sig.body
    end
    return whereparams
end

type_parameters(m::Method) = type_parameters(m.sig)
function type_parameters(sig)
    typeof_type = first(parameters(sig))  # will be e.g Type{Foo{P}} if it has any parameters
    typeof_type <: Type{<:Any} || return nothing

    function_type = first(parameters(typeof_type))  # will be e.g. Foo{P}
    parameter_types = parameters(function_type)
    return [name_of_type(type) for type in parameter_types]
end

function kwargs(m::Method)
    names = kwarg_names(m)
    isempty(names) && return nothing  # we know it has no keywords.
    # TODO: Enhance this to support more than just their names
    # see https://github.com/invenia/ExprTools.jl/issues/6
    return names
end

function kwarg_names(m::Method)
    mt = Base.get_methodtable(m)
    !isdefined(mt, :kwsorter) && return []  # no kwsorter means no keywords for sure.
    return Base.kwarg_decl(m, typeof(mt.kwsorter))
end
