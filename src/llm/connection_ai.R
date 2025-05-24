library(huggingfaceR)

.hf_token <- Sys.getenv("HF_API_TOKEN")
if (identical(.hf_token, "")) stop("HF_API_TOKEN is not set in .env")

.hf_model <- Sys.getenv(
  "HF_MODEL_ID",
  unset = "meta-llama/Llama-2-7b-chat-hf"
)

hf_complete <- function(prompt, max_tokens = 256) {
  res <- hf_llm_completion(
    model      = .hf_model,
    inputs     = prompt,
    parameters = list(max_new_tokens = max_tokens),
    api_token  = .hf_token
  )
  trimws(res$generated_text)
}
