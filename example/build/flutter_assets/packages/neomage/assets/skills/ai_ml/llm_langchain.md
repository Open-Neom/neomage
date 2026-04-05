# LangChain/LangGraph Agent Development

Build production-grade AI agent systems using LangChain 0.1+ and LangGraph with async patterns throughout.

- LangGraph state management: StateGraph with typed state (MessagesState or custom TypedDict), nodes, conditional edges, checkpointers
- Model stack: Claude Sonnet 4.5 as primary LLM; Voyage AI voyage-3-large for embeddings (recommended for Claude)
- Agent types: ReAct (create_react_agent for general tasks), Plan-and-Execute (separate planning/execution nodes), Multi-Agent (supervisor routing with Command[Literal[...]])
- Memory systems: ConversationTokenBufferMemory (windowed), ConversationSummaryMemory (compressed), ConversationEntityMemory (entity tracking), VectorStoreRetrieverMemory (semantic search)
- RAG: VoyageAIEmbeddings + PineconeVectorStore with hybrid search (alpha=0.5); rerank with Cohere; advanced patterns: HyDE, RAG-Fusion
- Tools: StructuredTool.from_function with Pydantic schema, async support, and error handling
- Production: FastAPI with StreamingResponse, LangSmith tracing, Prometheus metrics, structlog logging, Redis caching
- Always use async (ainvoke, astream); implement retry with exponential backoff; set timeouts on all operations
- State graph pattern: builder.add_node -> add_conditional_edges (router) -> compile(checkpointer=checkpointer)
