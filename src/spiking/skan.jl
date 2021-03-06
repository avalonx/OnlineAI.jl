
# Implementation of the SKAN neuron model from:
#   "Racing to Learn: Statistical Inference and Learning in a Single Spiking Neuron with Adaptive Kernels" Afshar et al 2014
#   "Turn Down That Noise: Synaptic Encoding of Afferent SNR in a Single Spiking Neuron" Afshar et al 2014


# "A component of a SKAN architecture"
# abstract AbstractSkan

export
    SkanParams,
    InputNeuron,
    SkanNeuron,
    SkanGroup,
    SkanSynapse,
    membrane_potential,
    step!


# -----------------------------------------------------------------------------

using Parameters

@with_kw immutable SkanParams{T<:Real}
    # Δt::Int = 1
    # ramp_step_rise::T = 
    ramp_step_adjustment::T = 1  # ddr
    ramp_step_min::T = 0         #
    ramp_step_max::T = 400
    ramp_step_initfunc::Function = () -> T(rand(100:200))
    # threshold_rise_initfunc::Function = (n) -> 40n
    # threshold_fall_initfunc::Function = (n) -> 100n
    # inhibitor_decay::T
    weight_init::T = 10000
    # weight_initfunc::Function = () -> 10000
    # weight_rise::T
    # weight_fall::T
end

# -----------------------------------------------------------------------------

"Represents an input spike train"
type InputNeuron <: SpikingNeuron
    spike::Bool
end
InputNeuron() = InputNeuron(false)
step!(neuron::InputNeuron) = nothing

# -----------------------------------------------------------------------------

"""
A SkanNeuron is modeled on Afshar et al's Synapto-Dendritic Kernel Adaptation (SKAN) framework,
which is a straightforward and efficient approximation of delayed spiking characteristics, and a linearly
updating alternative to the Spike Response Model (SRM), Hodgen-Huxley, or other similarly complex neuronal
models.  The model avoids multiplication and division, and has a smart normalization step using only left/right
shifts, thus compute power can be used for additional model expressivity instead of biological correctness.
"""
type SkanNeuron{T<:Real, S} <: SpikingNeuron
    incoming_synapses::S
    # outgoing_synapses::S
    pulse::Bool         # s(t): the soma output (pulse)... binary: on or off
    spike::Bool         # u(t): the initial spike. true when: !s(t-1) && s(t)
    potential::T        # ∑rᵢ(t): membrane potential
    threshold::T        # θ(t):   threshold voltage
    threshold_rise::T   # threshold change when increasing
    threshold_fall::T   # threshold change when decreasing
end

function membrane_potential{T<:Real}(neuron::SkanNeuron{T})
    sumrt = zero(T)
    for synapse in neuron.incoming_synapses
        sumrt += synapse.ramp
    end
    sumrt
end

# update the neurons' membrane potentials and update pulse/spike/threshold/potential
#   pulse(t) = sum(rᵢ(t)) > θ(t-1)  (for i ∈ incoming_synapses)
#   spike(t) = pulse(t) && !pulse(t-1)
function step!(neuron::SkanNeuron)
    potential = membrane_potential(neuron)

    # pulse while potential is above threshold
    # spike only in the first timestep of a pulse
    pulse = potential >= neuron.threshold
    neuron.spike = pulse && !neuron.pulse
    neuron.pulse = pulse

    # during a pulse, increase the threshold
    if pulse
        neuron.threshold += neuron.threshold_rise

    # when potential returns to rest, decrease the threshold
    elseif potential <= 0 && neuron.potential > 0
        neuron.threshold -= neuron.threshold_fall
    end

    # save the potential
    neuron.potential = potential
end

# -----------------------------------------------------------------------------

# group of SKAN neurons which have a shared inhibitory signal
type SkanGroup{T<:Real} <: AbstractVector{SkanNeuron{T}}
    neurons::Vector{SkanNeuron{T}}
    inhibitor::T
end
Base.size(group::SkanGroup) = size(group.neurons)
Base.getindex(group::SkanGroup, i::Integer) = group.neurons[i]

# connects a presynaptic SkanNeuron to a postsynaptic SkanNeuron
type SkanSynapse{T<:Real, S1<:SpikingNeuron, S2<:SpikingNeuron}
    presynaptic::S1
    postsynaptic::S2
    weight::T           # wᵢ(t): synaptic weight
    weight_adj_flag::T  # dᵢ(t): 1 on uᵢ(t)
    ramp::T             # rᵢ(t): ramp height
    ramp_step::T        # Δrᵢ(t): ramp height change per time period Δt
    ramp_flag::Int8     # pᵢ(t): state of the ramp-up/ramp-down flag {-1, 0, 1}
end

# -----------------------------------------------------------------------------





"One time step in a simulation"
function step!{N<:SpikingNeuron, S<:SkanSynapse}(params::SkanParams,
                                              neurons::AbstractArray{N},
                                              synapses::AbstractArray{S})

    # update the ramp vars for each synapse
    #   r(t) += p(t-1) * Δr(t-1)
    #   Δr(t) += ddr * s(t-1)
    for synapse in synapses
        synapse.ramp += synapse.ramp_flag * synapse.ramp_step
        synapse.ramp = max(0, synapse.ramp)
        if synapse.postsynaptic.pulse
            synapse.ramp_step += synapse.ramp_flag * params.ramp_step_adjustment
        end
    end

    # update the neurons
    for neuron in neurons
        step!(neuron)
    end

    # update the synaptic ramp flags
    for synapse in synapses
        if synapse.ramp_flag > 0 && synapse.ramp >= synapse.weight
            synapse.ramp_flag = -1
        elseif synapse.ramp_flag < 0 && synapse.ramp <= 0
            synapse.ramp_flag = 0
        elseif synapse.ramp_flag == 0 && synapse.presynaptic.spike
            synapse.ramp_flag = 1
        end
    end

end


# -----------------------------------------------------------------------------

