// Spinner loading verbs — ported from NeomClaw src/constants/spinnerVerbs.ts.

import 'dart:math';

/// 188 playful verbs for loading/spinner messages.
const List<String> spinnerVerbs = [
  'Accomplishing', 'Activating', 'Actualizing', 'Adapting', 'Administering',
  'Advancing', 'Aerobicizing', 'Aggregating', 'Aligning', 'Allocating',
  'Amalgamating', 'Amplifying', 'Analyzing', 'Anchoring', 'Applying',
  'Architecting', 'Assembling', 'Assessing', 'Assimilating', 'Augmenting',
  'Balancing', 'Beautifying', 'Beboppin\'', 'Benchmarking', 'Blossoming',
  'Booting', 'Bootstrapping', 'Brainstorming', 'Brewing', 'Bridging',
  'Buffering', 'Building', 'Calculating', 'Calibrating', 'Catalyzing',
  'Channeling', 'Charging', 'Choreographing', 'Ciphering', 'Clustering',
  'Coalescing', 'Collating', 'Compiling', 'Composing', 'Computing',
  'Concentrating', 'Conceptualizing', 'Condensing', 'Configuring', 'Conjuring',
  'Consolidating', 'Constructing', 'Contemplating', 'Converging', 'Cooking',
  'Coordinating', 'Correlating', 'Crafting', 'Crunching', 'Crystallizing',
  'Cultivating', 'Curating', 'Decoding', 'Deconstructing', 'Deliberating',
  'Deploying', 'Deriving', 'Designing', 'Devising', 'Digesting',
  'Distilling', 'Dreaming', 'Elaborating', 'Elevating', 'Elucidating',
  'Emanating', 'Embracing', 'Empowering', 'Encoding', 'Engineering',
  'Enhancing', 'Enriching', 'Envisioning', 'Establishing', 'Evaluating',
  'Evolving', 'Examining', 'Excavating', 'Experimenting', 'Extracting',
  'Fabricating', 'Facilitating', 'Fashioning', 'Fermenting', 'Filtering',
  'Firing', 'Flibbertigibbeting', 'Flourishing', 'Flowing', 'Focusing',
  'Forging', 'Formulating', 'Fostering', 'Founding', 'Fusing',
  'Galvanizing', 'Gathering', 'Generating', 'Germinating', 'Harmonizing',
  'Harnessing', 'Hatching', 'Hydrating', 'Hypothesizing', 'Igniting',
  'Illuminating', 'Imagining', 'Implementing', 'Improvising', 'Incubating',
  'Indexing', 'Inferring', 'Initializing', 'Innovating', 'Inspecting',
  'Integrating', 'Interpolating', 'Iterating', 'Journeying', 'Juggling',
  'Kindling', 'Knitting', 'Launching', 'Layering', 'Loading',
  'Machinating', 'Manifesting', 'Manufacturing', 'Mapping', 'Marinating',
  'Meditating', 'Mobilizing', 'Modeling', 'Modulating', 'Morphing',
  'Navigating', 'Nesting', 'Networking', 'Nurturing', 'Observing',
  'Operationalizing', 'Optimizing', 'Orchestrating', 'Organizing', 'Parsing',
  'Percolating', 'Permutating', 'Philosophizing', 'Piloting', 'Pioneering',
  'Polishing', 'Pondering', 'Processing', 'Progressing', 'Projecting',
  'Propagating', 'Prospecting', 'Prototyping', 'Pruning', 'Quantifying',
  'Radiating', 'Reasoning', 'Recalibrating', 'Reconnoitering', 'Refactoring',
  'Reflecting', 'Rendering', 'Resolving', 'Reverberating', 'Revolutionizing',
  'Ruminating', 'Scaffolding', 'Sculpting', 'Simmering', 'Simulating',
  'Sketching', 'Solving', 'Sparking', 'Speculating', 'Spinning',
  'Sprouting', 'Stabilizing', 'Strategizing', 'Streamlining', 'Structuring',
  'Symbioting', 'Synchronizing', 'Synthesizing', 'Tailoring', 'Theorizing',
  'Thinking', 'Tinkering', 'Transcending', 'Transforming', 'Transmuting',
  'Traversing', 'Tuning', 'Unfolding', 'Unifying', 'Weaving',
  'Wrangling', 'Zeroing',
];

/// Get a random spinner verb.
String getRandomSpinnerVerb() {
  return spinnerVerbs[Random().nextInt(spinnerVerbs.length)];
}
