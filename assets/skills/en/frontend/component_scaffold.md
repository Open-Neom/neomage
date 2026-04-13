# Component Scaffolding

Scaffold production-ready React/React Native components with TypeScript, tests, styles, and accessibility.

- Analyze component type (functional, page, layout, form, data-display) to determine structure and patterns
- Component file: typed props interface with JSDoc descriptions, hooks, handlers, accessible JSX with ARIA roles
- Platform detection: web components use CSS modules/styled-components/Tailwind; native uses StyleSheet.create
- React Native: use View/Text/TouchableOpacity, add accessible={true} and accessibilityLabel props
- Types file: export interface for props with required/optional flags, default values, and clear descriptions
- Tests: render with default props, assert role-based queries, test event handlers with fireEvent, run axe accessibility check
- Storybook stories: Meta with argTypes mapped to control types, Default and Interactive variants
- Index file: barrel exports for clean imports from the component directory
- Styling: CSS modules for scoped styles with CSS variables, styled-components for theme-aware components, Tailwind utility classes
- Every component gets: TypeScript types, test suite, style definitions, Storybook story, and barrel export
