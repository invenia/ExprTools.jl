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

    return filter!(kv->last(kv)!==nothing, def)  # filter out nonfields.
end


"""
    signature(sig::Type{<:Tuple})

Like `ExprTools.signature(::Method)` but on the underlying signature type-tuple, rather than
the Method`.
For `sig` being a tuple-type representing a methods type signature, this generates a
dictionary that can be passes to `ExprTools.combinedef` to define that function,
Provided that you assign the `:body` key on the dictionary first.

The quality of the output, in terms of matching names etc is not as high as for the
`signature(::Method)`, but all the key information is present; and the type-tuple is for
other purposes generally easier to manipulate.

Examples
```julia
julia> signature(Tuple{typeof(identity), Any})
Dict{Symbol, Any} with 2 entries:
  :name => :(op::typeof(identity))
  :args => Expr[:(x1::Any)]

julia> signature(Tuple{typeof(+), Vector{T}, Vector{T}} where T<:Number)
Dict{Symbol, Any} with 3 entries:
  :name        => :(op::typeof(+))
  :args        => Expr[:(x1::Array{var"##T#5492", 1}), :(x2::Array{var"##T#5492", 1})]
  :whereparams => Any[:(var"##T#5492" <: Number)]
```

# keywords

 - `hygienic_unionalls=false`: if set to `true` this forces name-hygine on the `TypeVar`s in 
   `UnionAll`s, regenerating each with a unique name via `gensym`. This shouldn't actually
   be required as they are scoped such that they are not supposed to leak. However, there is
   a long-standing [julia bug](https://github.com/JuliaLang/julia/issues/39876) that means 
   they do leak if they clash with function type-vars.
"""
function signature(orig_sig::Type{<:Tuple}; hygienic_unionalls=false)
    sig = hygienic_unionalls ? _truly_rename_unionall(orig_sig) : orig_sig
    def = Dict{Symbol, Any}()

    opT = parameters(sig)[1]
    def[:name] = :(op::$opT)

    arg_types = name_of_type.(argument_types(sig))
    arg_names = [Symbol(:x, ii) for ii in eachindex(arg_types)]
    def[:args] = Expr.(:(::), arg_names, arg_types)
    def[:whereparams] = where_parameters(sig)

    filter!(kv->last(kv)!==nothing, def)  # filter out nonfields.
    return def
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

module DummyThatHasOnlyDefaultImports end  # for working out visibility

function name_of_module(m::Module)
    if Base.is_root_module(m)
        return nameof(m)
    else
        return :($(name_of_module(parentmodule(m))).$(nameof(m)))
    end
end
function name_of_type(x::Core.TypeName)
    # TODO: could let user pass this in, then we could be using what is inscope for them
    # but this is not important as we will give a correct (if overly verbose) output as is.
    from = DummyThatHasOnlyDefaultImports
    if Base.isvisible(x.name, x.module, from)  # avoid qualifying things that are in scope
        return x.name
    else
        return :($(name_of_module(x.module)).$(x.name))
    end
end

name_of_type(x::Symbol) = QuoteNode(x)  # Literal type-param e.g. `Val{:foo}`
function name_of_type(x::T) where T  # Literal type-param e.g. `Val{1}`
    # If this error is thrown, there is an issue with out implementation
    isbits(x) || throw(DomainError((x, T), "not a valid type-param"))
    return x
end
name_of_type(tv::TypeVar) = tv.name
function name_of_type(x::DataType)
    name = name_of_type(x.name)
    # because tuples are varadic in number of type parameters having no parameters does not
    # mean you should not write the `{}`, so we special case them here.
    if isempty(x.parameters) && x != Tuple{}
        return name
    else
        parameter_names = map(name_of_type, x.parameters)
        return :($(name){$(parameter_names...)})
    end
end


function name_of_type(x::UnionAll)
    # we do nested union all unwrapping so we can make the more compact:
    # `foo{T,A} where {T, A}`` rather than the longer: `(foo{T,A} where T) where A`
    where_params = []
    while x isa UnionAll
        push!(where_params, where_constraint(x.var))
        x = x.body
    end

    name = name_of_type(x)
    return :($name where {$(where_params...)})
end

function name_of_type(x::Union)
    parameter_names = map(name_of_type, Base.uniontypes(x))
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

function where_constraint(x::TypeVar)
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
        push!(whereparams, where_constraint(sig.var))
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
    return map(name_of_type, parameter_types)
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



"""
    _truly_rename_unionall(@nospecialize(u))

For `u` being a `UnionAll` this replaces every `TypeVar` with  a new one with a `gensym`ed
names.
This shouldn't actually be required as they are scoped such that they are not supposed to leak. However, there is
a long standing [julia bug](https://github.com/JuliaLang/julia/issues/39876) that means 
they do leak if they clash with function type-vars.

Example:
```julia
julia> _truly_rename_unionall(Array{T, N} where {T<:Number, N})
Array{var"##T#2881", var"##N#2880"} where var"##N#2880" where var"##T#2881"<:Number
```

Note that the similar `Base.rename_unionall`, though `Base.rename_unionall` does not
`gensym` the names just replaces the instances with new instances with identical names.
"""
function _truly_rename_unionall(@nospecialize(u))
    isa(u, UnionAll) || return u
    body = _truly_rename_unionall(u.body)
    if body === u.body
        body = u
    else
        body = UnionAll(u.var, body)
    end
    var = u.var::TypeVar
    nv = TypeVar(gensym(var.name), var.lb, var.ub)
    return UnionAll(nv, body{nv})
end
