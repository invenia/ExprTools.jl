"""
    parameters(type)

Extracts the type-parameters of the `type`.

```jldoctest
julia> parameters(Foo{A, B, C}) == [A, B, C]
true
```
"""
parameters(sig::UnionAll) = parameters(sig.body)
parameters(sig::DataType) = sig.parameters
