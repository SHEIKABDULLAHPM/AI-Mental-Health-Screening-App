"""AI core modules: mood, risk, rag, recommendation, llm.

Each module exposes a class implementing a small protocol so the API layer and
service layer depend only on stable interfaces. Swapping providers (OpenAI,
local models, alternative vector stores) never touches HTTP code.
"""
