"""
    parameters(type)

Extracts the type-parameters of the `type`.

e.g. `parameters(Foo{A, B, C}) == [A, B, C]`
"""
parameters(sig::UnionAll) = parameters(sig.body)
parameters(sig::DataType) = sig.parameters
parameters(sig::Union) = Base.uniontypes(sig)