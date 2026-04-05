# C4 Component Level
Synthesize code-level documentation into logical components with boundaries, interfaces, and relationships.
- Group related code files into components based on domain, technical, or organizational boundaries
- Each component has: name, type (Application/Service/Library), technology, and purpose
- Document all interfaces with protocol (REST/GraphQL/gRPC/Events) and operation signatures
- List software features each component provides
- Show component relationships within a single container using C4Component Mermaid notation
- Link back to all contained c4-code files for drill-down navigation
- Create a master component index listing all components with relationship diagram
- Component diagrams zoom into one container, showing internal logical structure
- Include external dependencies: other containers and external systems the component uses
- Focus on logical grouping and responsibilities, not deployment -- that belongs at container level
