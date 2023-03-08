"""
    splitdef(ex::Expr; throw::Bool=true) -> Union{Dict{Symbol,Any}, Nothing}

Split a function definition expression into its various components including:

- `:head`: Expression head of the function definition (`:function`, `:(=)`, `:(->)`)
- `:name`: Name of the function (not present for anonymous functions)
- `:params`: Parametric types defined on constructors
- `:args`: Positional arguments of the function
- `:kwargs`: Keyword arguments of the function
- `:rtype`: Return type of the function
- `:whereparams`: Where parameters
- `:body`: Function body (not present for empty functions)
- `:anonhead` : Expression head of the function definition for an assigned anonymous  
  function. In this case, `head == `:(=)` and `anonhead` is either `:function` or `:(->)`.

All components listed may not be present in the returned dictionary with the exception of
`:head` which will always be present.

If the provided expression is not a function then an exception will be raised when
`throw=true`. Use `throw=false` avoid raising an exception and return `nothing` instead.

See also: [`combinedef`](@ref)
"""
function splitdef(ex::Expr; throw::Bool=true)
    def = Dict{Symbol,Any}()
    full_ex = ex  # Keep a reference to the full expression

    function invalid_def(section)
        if throw
            msg = "Function definition contains $section\n$(sprint(Meta.dump, full_ex))"
            Base.throw(ArgumentError(msg))
        else
            nothing
        end
    end

    if !(ex.head === :function || ex.head === :(=) || ex.head === :(->))
        return invalid_def("invalid function head `$(repr(ex.head))`")
    end

    def[:head] = ex.head

    if ex.head === :function && length(ex.args) == 1 && ex.args[1] isa Symbol
        # empty function definition
        def[:name] = ex.args[1]
        return def
    elseif length(ex.args) == 2  
        if ex.head === :(=) && ex.args[1] isa Symbol # `ex` defines an assigned anonymous function
            def[:name] = ex.args[1]         # name is on the left
            anondef = splitdef(ex.args[2])  # parse RHS into `anondef` dictionary
            def[:anonhead] = anondef[:head]
            return merge(anondef, def)  # keys in `def` take precedence
        else # Expect signature and body
            def[:body] = ex.args[2]
            ex = ex.args[1]  # Focus on the function signature
        end
    else
        quan = length(ex.args) > 2 ? "too many" : "too few"
        return invalid_def("$quan of expression arguments for `$(repr(def[:head]))`")
    end

    # Where parameters
    if ex isa Expr && ex.head === :where
        def[:whereparams] = Any[]

        while ex isa Expr && ex.head === :where
            append!(def[:whereparams], ex.args[2:end])
            ex = ex.args[1]
        end
    end

    # Return type
    if def[:head] !== :(->) && ex isa Expr && ex.head === :(::)
        def[:rtype] = ex.args[2]
        ex = ex.args[1]
    end

    # Determine if the function is anonymous
    anon = (
        def[:head] === :(->) ||
        def[:head] === :function && !(ex isa Expr && ex.head === :call)
    )

    # Arguments and keywords
    if ex isa Expr && (anon && ex.head === :tuple || !anon && ex.head === :call)
        i = anon ? 1 : 2

        if length(ex.args) >= i
            if ex.args[i] isa Expr && ex.args[i].head === :parameters
                def[:kwargs] = ex.args[i].args

                if length(ex.args) > i
                    def[:args] = ex.args[(i + 1):end]
                end
            else
                def[:args] = ex.args[i:end]
            end
        end
    elseif ex isa Expr && anon && ex.head === :block
        # Note: Short-form anonymous functions (:->) will use a block expression when the
        # arguments are divided by semi-colons but do not use commas:
        #
        # (;) -> ...
        # (x;) -> ...
        # (x;y) -> ...
        # (;x) -> ...  # Note: this is an exception to this rule

        for arg in ex.args
            arg isa LineNumberNode && continue

            if !haskey(def, :args)
                def[:args] = [arg]
            elseif !haskey(def, :kwargs)
                if arg isa Expr && arg.head == :(=)
                    def[:kwargs] = [:($(Expr(:kw, arg.args...)))]
                else
                    def[:kwargs] = [arg]
                end
            else
                return invalid_def("an invalid block expression as arguments")
            end
        end

        !haskey(def, :kwargs) && (def[:kwargs] = [])

    elseif def[:head] === :(->)
        def[:args] = [ex]
    else
        return invalid_def("invalid or missing arguments")
    end

    # Function name and type parameters
    if !anon
        ex = ex.args[1]

        if ex isa Expr && ex.head === :curly
            def[:params] = ex.args[2:end]
            ex = ex.args[1]
        end

        def[:name] = ex
    end

    return def
end

"""
    combinedef(def::Dict{Symbol,Any}) -> Expr

Create a function definition expression from various components. Typically used to construct
a function using the result of [`splitdef`](@ref).

If `def[:head]` is not provided it will default to `:function`.

For more details see the documentation on [`splitdef`](@ref).
"""
function combinedef(def::Dict{Symbol,Any})
    head = get(def, :head, :function)

    # Determine the name of the function including parameterization
    name = if haskey(def, :params)
        Expr(:curly, def[:name], def[:params]...)
    elseif haskey(def, :name)
        def[:name]
    else
        nothing
    end

    # Deal with assigned anonymous functions by recursively calling `combinedef` on a
    # suitable dictionary `_def` created from `def`, without modifying the latter.
    if haskey(def, :anonhead)
        _def = copy(def)
        _def[:head] = def[:anonhead]    # head of RHS anonymous function is `def[:anonhead]`
        delete!(_def, :anonhead)        # make sure, there is no endless recursion
        delete!(_def, :name)            # anonymous functions also do not have a name
        sig = combinedef(_def)          # call `combinedef` for the RHS
        return Expr(head, name, sig)    # early return, we only have to equate LHS and RHS
    end
    
    # Empty generic function definitions must not contain additional keys
    empty_extras = (:args, :kwargs, :rtype, :whereparams)
    if !haskey(def, :body) && any(k -> haskey(def, k), empty_extras)
        throw(ArgumentError(string(
            "Function definitions without a body must not contain keys: ",
            join(string.('`', repr.(setdiff(empty_extras, keys(def))), '`'), ", ", ", or "),
        )))
    end

    # Combine args and kwargs
    args = Any[]
    haskey(def, :kwargs) && push!(args, Expr(:parameters, def[:kwargs]...))
    haskey(def, :args) && append!(args, def[:args])

    # Create a partial function signature including the name and arguments
    sig = if name !== nothing
        :($name($(args...)))  # Equivalent to `Expr(:call, name, args...)` but faster
    elseif head === :(->) && length(args) == 1 && !haskey(def, :kwargs)
        args[1]
    else
        :(($(args...),))  # Equivalent to `Expr(:tuple, args...)` but faster
    end

    # Add the return type
    if haskey(def, :rtype)
        sig = Expr(:(::), sig, def[:rtype])
    end

    # Add any where parameters. Note: Always uses the curly where syntax
    if haskey(def, :whereparams)
        sig = Expr(:where, sig, def[:whereparams]...)
    end

    func = if haskey(def, :body)
        Expr(head, sig, def[:body])
    else
        Expr(head, name)
    end

    return func
end
