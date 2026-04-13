# Threat Modeling

Expert threat modeling: STRIDE, PASTA, attack trees, DFDs, and security requirement extraction.

- Process: define scope and trust boundaries, create data flow diagrams, identify assets and entry points, apply STRIDE, build attack trees, score threats, design mitigations, document residual risks
- DFDs: map processes, data stores, data flows, external entities, and trust boundaries; threats live at boundary crossings
- STRIDE: apply to each DFD element systematically; processes get all 6 categories, data stores focus on TID, flows on TID
- Attack trees: model complex attack paths with AND/OR nodes; useful for identifying cheapest attack and prioritizing defense
- PASTA (Process for Attack Simulation and Threat Analysis): 7-stage risk-centric approach for business-aligned threat modeling
- Scoring: use CVSS for individual vulnerabilities, DREAD or custom matrix for threat-level prioritization
- Involve developers in threat modeling sessions; they know the system best and will implement the mitigations
- Focus on data flows over components; consider insider threats alongside external attackers
- Link threats to security requirements, then requirements to controls, then controls to tests
- Keep threat models living documents: update after architecture changes, incidents, or new feature additions
