# default node types in IIF

SamplableBelief = Union{Distributions.Distribution, KernelDensityEstimate.BallTreeDensity, AliasingScalarSampler}


"""
$(TYPEDEF)

Most basic continuous scalar variable a `::FactorGraph` object.
"""
struct ContinuousScalar <: InferenceVariable
  dims::Int
  labels::Vector{String}
  manifolds::Tuple{Symbol}
  ContinuousScalar(;labels::Vector{<:AbstractString}=String[], manifolds::Tuple{Symbol}=(:Euclid,)) = new(1, labels, manifolds)
end

"""
$(TYPEDEF)

Continuous variable of dimension `.dims` on manifold `.manifolds`.
"""
struct ContinuousMultivariate{T1 <: Tuple} <: InferenceVariable
  dims::Int
  labels::Vector{String}
  manifolds::T1
  ContinuousMultivariate{T}() where {T} = new()
  ContinuousMultivariate{T}(x::Int;labels::Vector{<:AbstractString}=String[], manifolds::T=(:Euclid,)) where {T <: Tuple} = new(x, labels, manifolds)
end

function ContinuousMultivariate(x::Int;
                                labels::Vector{<:AbstractString}=String[],
                                manifolds::T1=(:Euclid,)  )  where {T1 <: Tuple}
  #
  @show maniT = length(manifolds) < x ? ([manifolds[1] for i in 1:x]...,) : manifolds
  ContinuousMultivariate{typeof(maniT)}(x, labels=labels, manifolds=maniT)
end


"""
$(TYPEDEF)

Default prior on all dimensions of a variable node in the factor graph.  `Prior` is
not recommended when non-Euclidean dimensions are used in variables.
"""
struct Prior{T} <: IncrementalInference.FunctorSingleton where T <: SamplableBelief
  Z::T
end
getSample(s::Prior, N::Int=1) = (reshape(rand(s.Z,N),:,N), )

"""
$(TYPEDEF)

Partial prior belief (absolute data) on any variable, given `<:SamplableBelief` and which dimensions of the intended variable.
"""
struct PartialPrior{T,P} <: IncrementalInference.FunctorSingleton where {T <: SamplableBelief, P <: Tuple}
  Z::T
  partial::P
end
PartialPrior(z::T, par::P) where {T <: SamplableBelief, P<:Tuple} = PartialPrior{T, P}(z, par)
getSample(s::PartialPrior, N::Int=1) = (reshape(rand(s.Z,N),:,N), )



"""
$(TYPEDEF)

Default linear offset between two scalar variables.
"""
struct LinearConditional{T} <: IncrementalInference.FunctorPairwise where T <: SamplableBelief
  Z::T
end
getSample(s::LinearConditional, N::Int=1) = (reshape(rand(s.Z,N),:,N), )
function (s::LinearConditional)(res::Array{Float64},
                                userdata::FactorMetadata,
                                idx::Int,
                                meas::Tuple{Array{Float64, 2}},
                                X1::Array{Float64,2},
                                X2::Array{Float64,2}  )
  #
  res[1] = meas[1][idx] - (X2[1,idx] - X1[1,idx])
  nothing
end


"""
$(TYPEDEF)

Define a categorical mixture of prior beliefs on a variable.
"""
struct MixturePrior{T} <: IncrementalInference.FunctorSingleton where {T <: SamplableBelief}
  Z::Vector{T}
  C::Distributions.Categorical
  MixturePrior{T}() where T  = new{T}()
  MixturePrior{T}(z::Vector{T}, c::Distributions.Categorical) where {T <: SamplableBelief} = new{T}(z, c)
  MixturePrior{T}(z::Vector{T}, p::Vector{Float64}) where {T <: SamplableBelief} = MixturePrior{T}(z, Distributions.Categorical(p))
end
MixturePrior(z::Vector{T}, c::Union{Distributions.Categorical, Vector{Float64}}) where {T <: SamplableBelief} = MixturePrior{T}(z, c)

getSample(s::MixturePrior, N::Int=1) = (reshape.(rand.(s.Z, N),1,:)..., rand(s.C, N))


"""
$(TYPEDEF)

Define a categorical mixture of (relative) likelihood beliefs between any two variables.
"""
struct MixtureLinearConditional{T} <: IncrementalInference.FunctorPairwise
  Z::Vector{T}
  C::Distributions.Categorical
  MixtureLinearConditional{T}() where T  = new{T}()
  MixtureLinearConditional{T}(z::Vector{T}, c::Distributions.Categorical) where {T <: SamplableBelief} = new{T}(z, c)
  MixtureLinearConditional{T}(z::Vector{T}, p::Vector{Float64}) where {T <: SamplableBelief} = MixtureLinearConditional{T}(z, Distributions.Categorical(p))
end
MixtureLinearConditional(z::Vector{T}, c::Union{Distributions.Categorical, Vector{Float64}}) where {T <: SamplableBelief} = MixtureLinearConditional{T}(z, c)

getSample(s::MixtureLinearConditional, N::Int=1) = (reshape.(rand.(s.Z, N),1,:)..., rand(s.C, N))
function (s::MixtureLinearConditional)(res::Array{Float64},
                               userdata::FactorMetadata,
                               idx::Int,
                               meas::Tuple,
                               X1::Array{Float64,2},
                               X2::Array{Float64,2}  )
  #
  res[1] = meas[meas[end][idx]][idx] - (X2[1,idx] - X1[1,idx])
  nothing
end



## packed types are still developed by hand.  Future versions would likely use a @packable macro to write Protobuf safe versions of factors

"""
$(TYPEDEF)

Serialization type for Prior.
"""
mutable struct PackedPrior <: PackedInferenceType
  Z::String
  PackedPrior() = new()
  PackedPrior(z::AS) where {AS <: AbstractString} = new(z)
end
function convert(::Type{PackedPrior}, d::Prior)
  PackedPrior(string(d.Z))
end
function convert(::Type{Prior}, d::PackedPrior)
  Prior(extractdistribution(d.Z))
end


"""
$(TYPEDEF)

Serialization type for `PartialPrior`.
"""
mutable struct PackedPartialPrior <: PackedInferenceType
  Z::String
  partials::Vector{Int}
  PackedPartialPrior() = new()
  PackedPartialPrior(z::AS) where {AS <: AbstractString} = new(z)
end
function convert(::Type{PackedPartialPrior}, d::PartialPrior)
  PackedPartialPrior(string(d.Z), [d.partial...;])
end
function convert(::Type{PartialPrior}, d::PackedPartialPrior)
  PartialPrior(extractdistribution(d.Z),(d.partials...,))
end


"""
$(TYPEDEF)

Serialization type for `LinearConditional` binary factor.
"""
mutable struct PackedLinearConditional <: PackedInferenceType
  Z::String
  PackedLinearConditional() = new()
  PackedLinearConditional(z::AS) where {AS <: AbstractString} = new(z)
end
function convert(::Type{PackedLinearConditional}, d::LinearConditional)
  PackedLinearConditional(string(d.Z))
end
function convert(::Type{LinearConditional}, d::PackedLinearConditional)
  LinearConditional(extractdistribution(d.Z))
end


"""
$(TYPEDEF)

Serialization type for `MixtureLinearConditional`.
"""
mutable struct PackedMixtureLinearConditional <: PackedInferenceType
  strs::Vector{String}
  cat::String
  PackedMixtureLinearConditional() = new()
  PackedMixtureLinearConditional(z::Vector{<:AbstractString}, cstr::AS) where {AS <: AbstractString} = new(z, cstr)
end
function convert(::Type{PackedMixtureLinearConditional}, d::MixtureLinearConditional)
  PackedMixtureLinearConditional(string.(d.Z), string(d.C))
end
function convert(::Type{MixtureLinearConditional}, d::PackedMixtureLinearConditional)
  MixtureLinearConditional(extractdistribution.(d.strs), extractdistribution(d.cat))
end



"""
$(TYPEDEF)

Serialization type for `MixedPrior`.
"""
mutable struct PackedMixturePrior <: PackedInferenceType
  strs::Vector{String}
  cat::String
  PackedMixturePrior() = new()
  PackedMixturePrior(z::Vector{<:AbstractString}, cstr::AS) where {AS <: AbstractString} = new(z, cstr)
end
function convert(::Type{PackedMixturePrior}, d::MixturePrior)
  PackedMixturePrior(string.(d.Z), string(d.C))
end
function convert(::Type{MixturePrior}, d::PackedMixturePrior)
  MixturePrior(extractdistribution.(d.strs), extractdistribution(d.cat))
end
