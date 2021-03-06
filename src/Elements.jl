module Elements

import Genie
using Stipple

import Genie.Renderer.Html: HTMLString, normal_element
import Genie.Renderer.Json.JSONParser.JSONText

export root, elem, vm, @iif, @elsiif, @els, @text, @bind, @data, @click, @on

#===#

function root(app::M)::String where {M<:ReactiveModel}
  Genie.Generator.validname(typeof(app) |> string)
end

function root(app::Type{M})::String where {M<:ReactiveModel}
  Genie.Generator.validname(app |> string)
end

function elem(app::M)::String where {M<:ReactiveModel}
  "#$(root(app))"
end

const vm = root

#===#

function vue_integration(model::M; vue_app_name::String, endpoint::String, channel::String, debounce::Int)::String where {M<:ReactiveModel}
  vue_app = replace(Genie.Renderer.Json.JSONParser.json(model |> Stipple.render), "\"{" => " {")
  vue_app = replace(vue_app, "}\"" => "} ")
  vue_app = replace(vue_app, '"' => "'")

  output = raw"""
    const watcherMixin = {
      methods: {
        $withoutWatchers: function (cb, filter) {
          let ww = (filter === null) ? this._watchers : [];

          if (typeof(filter) == "string") {
            this._watchers.forEach((w) => { if (w.expression == filter) {ww.push(w)} } )
          } else { // if it is a true regex
            this._watchers.forEach((w) => { if (w.expression.match(filter)) {ww.push(w)} } )
          }

          const watchers = ww.map((watcher) => ({ cb: watcher.cb, sync: watcher.sync }));

          for (let index in ww) {
            ww[index].cb = () => null;
            ww[index].sync = true;
          }

          cb();

          for (let index in ww) {
            ww[index].cb = watchers[index].cb;
            ww[index].sync = watchers[index].sync;
          }

        },

        updateField: function (field, newVal) {
          this.$withoutWatchers( () => {this[field] = newVal }, "function () {return this." + field + "}");
        }
      }
    }
    """

  output *= "\nvar $vue_app_name = new Vue($vue_app);\n\n"

  for field in fieldnames(typeof(model))
    output *= Stipple.watch(vue_app_name, getfield(model, field), field, channel, debounce, model)
  end

  output *= """

  window.parse_payload = function(payload){
    if (payload.key) {
      window.$(vue_app_name).updateField(payload.key, payload.value);
    }
  }

  window.onload = function() {
    console.log("Loading completed");
    $vue_app_name.\$forceUpdate();
  }
  """

  output = replace(replace(repr(output), r"\\'"=>"'"), "'" => '"')

  output[2:prevind(output, lastindex(output))]
end

#===#

macro iif(expr)
  :( :( "v-if='$($(esc(expr)))'" ) )
end

macro elsiif(expr)
  :( "v-else-if='$($(esc(expr)))'" )
end

macro els(expr)
  :( "v-else='$($(esc(expr)))'" )
end

macro text(expr)
  quote
    directive = occursin(" | ", string($(esc(expr)))) ? ":text-content.prop" : "v-text"
    "$(directive)='$($(esc(expr)))'"
  end
end

"""
`@bind(expr, [type])`

Binds a model parameter to a quasar or vue component, optionally defining the parameter type.

`@bind(:xparam)` or `@bind(:xparam, :number)
"""
macro bind(expr)
  :( "v-model='$($(esc(expr)))'" )
end

macro bind(expr, type)
  :( "v-model.$($(esc(type)))='$($(esc(expr)))'" )
end

macro data(expr)
  quote
    x = $(esc(expr))
    if typeof(x) <: Union{AbstractString, Symbol}
      Symbol(x)
    else
      startswith("$x", "Any[") ? JSONText(":" * "$x"[4:end]) : JSONText(":$x")
    end
  end
end

"""
`@click(expr)`

Defines a js routine that is called by a click of the quasar component.
If a symbol argument is supplied, `@click` sets this value to true.

`@click("savefile = true")` or `@click("myjs_func();")` or `@click(:button)`

Modifers can be appended:
```
@click(:me, :native)
# "@click.native='me = true'"
```
"""
macro click(expr, mode="")
  quote
    x = $(esc(expr))
    m = $(esc(mode))
    if x isa Symbol
      """@click$(m == "" ? "" : ".$m")='$x = true'"""
    else
      "@click='$(replace(x, "'" => raw"\'"))'"
    end
  end
end

"""
`on(action, expr)`

Defines a js routine that is called by the given `action` of the quasar component, e.g. `:click`, `:input`

`@on(:click, "savefile = true")` or `@on("input.native", "myjs_func();")`
"""
macro on(args, expr)
  :( "v-on:$(string($(esc(args))))='$(replace($(esc(expr)),"'" => raw"\'"))'" )
end

#===#

include(joinpath("elements", "stylesheet.jl"))

end
