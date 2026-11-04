
//
// Copyright RIME Developers
// Distributed under the BSD License
//
// 2013-10-17 GONG Chen <chen.sst@gmail.com>
//

#include <rime_api.h>
#include <rime/common.h>
#include <rime/registry.h>

// built-in components
#include <rime/config.h>
#include <rime/config/plugins.h>
#include <rime/schema.h>

#include <cstdio>
#include "lua/lib/lua_templates.h"
#include "lua/lua_gears.h"

#include <rime/gear/abc_segmentor.h>
#include <rime/gear/affix_segmentor.h>
#include <rime/gear/ascii_composer.h>
#include <rime/gear/ascii_segmentor.h>
#include <rime/gear/charset_filter.h>
#include <rime/gear/chord_composer.h>
#include <rime/gear/echo_translator.h>
#include <rime/gear/editor.h>
#include <rime/gear/fallback_segmentor.h>
#include <rime/gear/history_translator.h>
#include <rime/gear/key_binder.h>
#include <rime/gear/matcher.h>
#include <rime/gear/navigator.h>
#include <rime/gear/punctuator.h>
#include <rime/gear/recognizer.h>
#include <rime/gear/reverse_lookup_filter.h>
#include <rime/gear/reverse_lookup_translator.h>
#include <rime/gear/schema_list_translator.h>
#include <rime/gear/script_translator.h>
#include <rime/gear/selector.h>
#include <rime/gear/shape.h>
#include <rime/gear/simplifier.h>
#include <rime/gear/single_char_filter.h>
#include <rime/gear/speller.h>
#include <rime/gear/switch_translator.h>
#include <rime/gear/table_translator.h>
#include <rime/gear/uniquifier.h>

void types_init(lua_State *L);

static bool file_exists(const char *fname) noexcept {
  FILE * const fp = fopen(fname, "r");
  if (fp) {
    fclose(fp);
    return true;
  }
  return false;
}


static void lua_init(lua_State *L) {
  const auto user_dir = std::string(RimeGetUserDataDir());
  const auto shared_dir = std::string(RimeGetSharedDataDir());

  types_init(L);
  lua_getglobal(L, "package");
  lua_pushfstring(L, "%s%slua%s?.lua;"
                     "%s%slua%s?%sinit.lua;"
                     "%s%slua%s?.lua;"
                     "%s%slua%s?%sinit.lua;",
                  user_dir.c_str(), LUA_DIRSEP, LUA_DIRSEP,
                  user_dir.c_str(), LUA_DIRSEP, LUA_DIRSEP, LUA_DIRSEP,
                  shared_dir.c_str(), LUA_DIRSEP, LUA_DIRSEP,
                  shared_dir.c_str(), LUA_DIRSEP, LUA_DIRSEP, LUA_DIRSEP);
  lua_getfield(L, -2, "path");
  lua_concat(L, 2);
  lua_setfield(L, -2, "path");
  lua_pop(L, 1);

  const auto user_file = user_dir + LUA_DIRSEP "rime.lua";
  const auto shared_file = shared_dir + LUA_DIRSEP "rime.lua";

  // use the user_file first
  // use the shared_file if the user_file doesn't exist
  if (file_exists(user_file.c_str())) {
    if (luaL_dofile(L, user_file.c_str())) {
      const char *e = lua_tostring(L, -1);
      LOG(ERROR) << "rime.lua error: " << e;
      lua_pop(L, 1);
    }
  } else if (file_exists(shared_file.c_str())) {
    if (luaL_dofile(L, shared_file.c_str())) {
      const char *e = lua_tostring(L, -1);
      LOG(ERROR) << "rime.lua error: " << e;
      lua_pop(L, 1);
    }
  } else {
    LOG(INFO) << "rime.lua info: rime.lua should be either in the "
                 "rime user data directory or in the rime shared "
                 "data directory";
  }
}

using namespace rime;
static void rime_core_initialize() {
  LOG(INFO) << "registering core components.";
  Registry& r = Registry::instance();

  auto config_builder = new ConfigComponent<ConfigBuilder>(
      [&](ConfigBuilder* builder) {
        builder->InstallPlugin(new AutoPatchConfigPlugin);
        builder->InstallPlugin(new DefaultConfigPlugin);
        builder->InstallPlugin(new LegacyPresetConfigPlugin);
        builder->InstallPlugin(new LegacyDictionaryConfigPlugin);
        builder->InstallPlugin(new BuildInfoPlugin);
        builder->InstallPlugin(new SaveOutputPlugin);
      });
  r.Register("config_builder", config_builder);

  auto config_loader =
      new ConfigComponent<ConfigLoader, DeployedConfigResourceProvider>;
  r.Register("config", config_loader);
  r.Register("schema", new SchemaComponent(config_loader));

  auto user_config =
      new ConfigComponent<ConfigLoader, UserConfigResourceProvider>(
          [](ConfigLoader* loader) {
            loader->set_auto_save(true);
          });
  r.Register("user_config", user_config);

  LOG(INFO) << "registering components from module 'gears'.";

  // processors
  r.Register("ascii_composer", new Component<AsciiComposer>);
  r.Register("chord_composer", new Component<ChordComposer>);
  r.Register("express_editor", new Component<ExpressEditor>);
  r.Register("fluid_editor", new Component<FluidEditor>);
  r.Register("fluency_editor", new Component<FluidEditor>);  // alias
  r.Register("key_binder", new Component<KeyBinder>);
  r.Register("navigator", new Component<Navigator>);
  r.Register("punctuator", new Component<Punctuator>);
  r.Register("recognizer", new Component<Recognizer>);
  r.Register("selector", new Component<Selector>);
  r.Register("speller", new Component<Speller>);
  r.Register("shape_processor", new Component<ShapeProcessor>);

  // segmentors
  r.Register("abc_segmentor", new Component<AbcSegmentor>);
  r.Register("affix_segmentor", new Component<AffixSegmentor>);
  r.Register("ascii_segmentor", new Component<AsciiSegmentor>);
  r.Register("matcher", new Component<Matcher>);
  r.Register("punct_segmentor", new Component<PunctSegmentor>);
  r.Register("fallback_segmentor", new Component<FallbackSegmentor>);

  // translators
  r.Register("echo_translator", new Component<EchoTranslator>);
  r.Register("punct_translator", new Component<PunctTranslator>);
  r.Register("table_translator", new Component<TableTranslator>);
  r.Register("script_translator", new Component<ScriptTranslator>);
  r.Register("r10n_translator", new Component<ScriptTranslator>);  // alias
  r.Register("reverse_lookup_translator",
             new Component<ReverseLookupTranslator>);
  r.Register("schema_list_translator", new Component<SchemaListTranslator>);
  r.Register("switch_translator", new Component<SwitchTranslator>);
  r.Register("history_translator", new Component<HistoryTranslator>);

  // filters
  r.Register("simplifier", new Component<Simplifier>);
  r.Register("uniquifier", new Component<Uniquifier>);
  if (!r.Find("charset_filter")) {  // allow improved implementation
    r.Register("charset_filter", new Component<CharsetFilter>);
  }
  r.Register("cjk_minifier", new Component<CharsetFilter>);  // alias
  r.Register("reverse_lookup_filter", new Component<ReverseLookupFilter>);
  r.Register("single_char_filter", new Component<SingleCharFilter>);

  // formatters
  r.Register("shape_formatter", new Component<ShapeFormatter>);

  LOG(INFO) << "registering components from module 'lua'.";

  an<Lua> lua(new Lua);
  lua->to_state(lua_init);

  r.Register("lua_translator", new LuaComponent<LuaTranslator>(lua));
  r.Register("lua_filter", new LuaComponent<LuaFilter>(lua));
  r.Register("lua_segmentor", new LuaComponent<LuaSegmentor>(lua));
  r.Register("lua_processor", new LuaComponent<LuaProcessor>(lua));
}

static void rime_core_finalize() {
  // registered components have been automatically destroyed prior to this call
}

RIME_REGISTER_MODULE(core)


