module Elements

import Genie
using Stipple

import Genie.Renderer.Html: HTMLString, normal_element

export root, elem, vm, @iif, @elsiif, @els, @text, @bind, @data, @click, @on

#===#

function root(app::M, channel::String = Genie.config.webchannels_default_route)::String where {M<:ReactiveModel}
  Genie.Generator.validname(typeof(app) |> string) *
    (channel == Genie.config.webchannels_default_route ? "" : "-$channel")
end

function root(app::Type{M}, channel::String = Genie.config.webchannels_default_route)::String where {M<:ReactiveModel}
  Genie.Generator.validname(app |> string) *
    (channel == Genie.config.webchannels_default_route ? "" : "-$channel")
end

function elem(app::M, channel::String = Genie.config.webchannels_default_route)::String where {M<:ReactiveModel}
  "#$(root(app, channel))"
end

const vm = root

#===#

function vue_integration(model::M; vue_app_name::String, endpoint::String, channel::String, debounce::Int)::String where {M<:ReactiveModel}
  vue_app = replace(Genie.Renderer.Json.JSONParser.json(Stipple.render(model, channel = channel)) , "\"{" => " {")
  vue_app = replace(vue_app, "}\"" => "} ")
  vue_app = replace(vue_app, "\\\\" => "\\")

  output = raw"""
    var watcherMixin = {
      methods: {
        \$withoutWatchers: function (cb, filter) {
          let ww = (filter == null) ? this._watchers : []
          if (typeof(filter) == "string") {
            this._watchers.forEach((w) => { if (w.expression == filter) {ww.push(w)} } )
          } else { // if it is a true regex
            this._watchers.forEach((w) => { if (w.expression.match(filter)) {ww.push(w)} } )
          }
          const watchers = ww.map((watcher) => ({ cb: watcher.cb, sync: watcher.sync }))
          for (let index in ww) {
            ww[index].cb = () => null
            ww[index].sync = true
          }
          cb()
          for (let index in ww) {
            ww[index].cb = watchers[index].cb
            ww[index].sync = watchers[index].sync
          }
        },
        updateField: function (field, newVal) {
          this.\$withoutWatchers( () => {this[field] = newVal }, "function () {return this." + field + "}")
        }
      }
    }
    """

  output *= """
    if (typeof($vue_app_name) == 'undefined') { var $vue_app_name = {} }
    $(vue_app_name)['$channel'] = new Vue($vue_app);\n\n
    """

  for field in fieldnames(typeof(model))
    output *= Stipple.watch(vue_app_name * "['$channel']", getfield(model, field), field, channel, debounce, model)
  end

  output *= """

  if (typeof(stippleApps) == 'undefined') { var stippleApps = {} }
  stippleApps['$channel'] = $vue_app_name['$channel']
  window.parse_payload = function(payload, channel){
    if (payload.key) {
      stippleApps[channel].updateField(payload.key, payload.value)
      let vStr = payload.value.toString()
      vStr = vStr.length < 60 ? vStr : vStr.substring(0, 55) + ' ...'
      window.console.log("server update (" + channel + "): ", payload.key + ': ' + vStr)
    } else {
      window.console.log("server says: ", payload)
    }
  }
  """
end

#===#

macro iif(expr)
  "v-if='$(startswith(string(expr), ":") ? string(expr)[2:end] : expr)'"
end

macro elsiif(expr)
  "v-else-if='$(startswith(string(expr), ":") ? string(expr)[2:end] : expr)'"
end

macro els(expr)
  "v-else='$(startswith(string(expr), ":") ? string(expr)[2:end] : expr)'"
end

macro text(expr)
  directive = occursin(" | ", string(expr)) ? ":text-content.prop" : "v-text"
  "$(directive)='$(startswith(string(expr), ":") ? string(expr)[2:end] : expr)'"
end

macro bind(expr)
  "v-model='$(startswith(string(expr), ":") ? string(expr)[2:end] : expr)'"
end

macro data(expr)
  :(Symbol($expr))
end

macro click(expr)
  "@click='$(startswith(string(expr), ":") ? string(expr)[2:end] : expr)'"
end

macro on(args, expr)
  "v-on:$(string(args))='$(startswith(string(expr), ":") ? string(expr)[2:end] : expr)'"
end

#===#

include(joinpath("elements", "stylesheet.jl"))

end
