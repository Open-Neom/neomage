// Spinner loading verbs — ported from neomagent src/constants/spinnerVerbs.ts.

import 'dart:math';

/// Configuration for customizing spinner verbs via settings.
class SpinnerVerbsConfig {
  /// How custom verbs interact with the defaults.
  ///
  /// - `replace`: use only the custom verbs (falls back to defaults if empty).
  /// - `append`: add custom verbs after the defaults.
  final SpinnerVerbsMode mode;

  /// Custom verb strings to replace or append.
  final List<String> verbs;

  const SpinnerVerbsConfig({required this.mode, required this.verbs});
}

/// Mode controlling how custom spinner verbs are applied.
enum SpinnerVerbsMode {
  /// Replace the default verbs entirely.
  replace,

  /// Append custom verbs to the defaults.
  append,
}

/// The 188 default playful loading-spinner verbs.
const List<String> spinnerVerbs = [
  'Accomplishing',
  'Actioning',
  'Actualizing',
  'Architecting',
  'Baking',
  'Beaming',
  "Beboppin'",
  'Befuddling',
  'Billowing',
  'Blanching',
  'Bloviating',
  'Boogieing',
  'Boondoggling',
  'Booping',
  'Bootstrapping',
  'Brewing',
  'Bunning',
  'Burrowing',
  'Calculating',
  'Canoodling',
  'Caramelizing',
  'Cascading',
  'Catapulting',
  'Cerebrating',
  'Channeling',
  'Channelling',
  'Choreographing',
  'Churning',
  'Clauding',
  'Coalescing',
  'Cogitating',
  'Combobulating',
  'Composing',
  'Computing',
  'Concocting',
  'Considering',
  'Contemplating',
  'Cooking',
  'Crafting',
  'Creating',
  'Crunching',
  'Crystallizing',
  'Cultivating',
  'Deciphering',
  'Deliberating',
  'Determining',
  'Dilly-dallying',
  'Discombobulating',
  'Doing',
  'Doodling',
  'Drizzling',
  'Ebbing',
  'Effecting',
  'Elucidating',
  'Embellishing',
  'Enchanting',
  'Envisioning',
  'Evaporating',
  'Fermenting',
  'Fiddle-faddling',
  'Finagling',
  'Flambéing',
  'Flibbertigibbeting',
  'Flowing',
  'Flummoxing',
  'Fluttering',
  'Forging',
  'Forming',
  'Frolicking',
  'Frosting',
  'Gallivanting',
  'Galloping',
  'Garnishing',
  'Generating',
  'Gesticulating',
  'Germinating',
  'Gitifying',
  'Grooving',
  'Gusting',
  'Harmonizing',
  'Hashing',
  'Hatching',
  'Herding',
  'Honking',
  'Hullaballooing',
  'Hyperspacing',
  'Ideating',
  'Imagining',
  'Improvising',
  'Incubating',
  'Inferring',
  'Infusing',
  'Ionizing',
  'Jitterbugging',
  'Julienning',
  'Kneading',
  'Leavening',
  'Levitating',
  'Lollygagging',
  'Manifesting',
  'Marinating',
  'Meandering',
  'Metamorphosing',
  'Misting',
  'Moonwalking',
  'Moseying',
  'Mulling',
  'Mustering',
  'Musing',
  'Nebulizing',
  'Nesting',
  'Newspapering',
  'Noodling',
  'Nucleating',
  'Orbiting',
  'Orchestrating',
  'Osmosing',
  'Perambulating',
  'Percolating',
  'Perusing',
  'Philosophising',
  'Photosynthesizing',
  'Pollinating',
  'Pondering',
  'Pontificating',
  'Pouncing',
  'Precipitating',
  'Prestidigitating',
  'Processing',
  'Proofing',
  'Propagating',
  'Puttering',
  'Puzzling',
  'Quantumizing',
  'Razzle-dazzling',
  'Razzmatazzing',
  'Recombobulating',
  'Reticulating',
  'Roosting',
  'Ruminating',
  'Sautéing',
  'Scampering',
  'Schlepping',
  'Scurrying',
  'Seasoning',
  'Shenaniganing',
  'Shimmying',
  'Simmering',
  'Skedaddling',
  'Sketching',
  'Slithering',
  'Smooshing',
  'Sock-hopping',
  'Spelunking',
  'Spinning',
  'Sprouting',
  'Stewing',
  'Sublimating',
  'Swirling',
  'Swooping',
  'Symbioting',
  'Synthesizing',
  'Tempering',
  'Thinking',
  'Thundering',
  'Tinkering',
  'Tomfoolering',
  'Topsy-turvying',
  'Transfiguring',
  'Transmuting',
  'Twisting',
  'Undulating',
  'Unfurling',
  'Unravelling',
  'Vibing',
  'Waddling',
  'Wandering',
  'Warping',
  'Whatchamacalliting',
  'Whirlpooling',
  'Whirring',
  'Whisking',
  'Wibbling',
  'Working',
  'Wrangling',
  'Zesting',
  'Zigzagging',
];

/// Returns the active spinner verbs list, respecting user configuration.
///
/// When [config] is `null`, returns the default [spinnerVerbs].
/// When mode is [SpinnerVerbsMode.replace], returns the custom verbs
/// (or defaults if the custom list is empty).
/// When mode is [SpinnerVerbsMode.append], returns the defaults followed
/// by the custom verbs.
List<String> getSpinnerVerbs([SpinnerVerbsConfig? config]) {
  if (config == null) return spinnerVerbs;

  switch (config.mode) {
    case SpinnerVerbsMode.replace:
      return config.verbs.isNotEmpty ? config.verbs : spinnerVerbs;
    case SpinnerVerbsMode.append:
      return [...spinnerVerbs, ...config.verbs];
  }
}

/// Returns a random spinner verb from the active list.
String getRandomSpinnerVerb([SpinnerVerbsConfig? config]) {
  final verbs = getSpinnerVerbs(config);
  return verbs[Random().nextInt(verbs.length)];
}
