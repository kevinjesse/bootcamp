import time
import random
from typing import Dict
import torch

from datasets import load_dataset, Dataset
import pandas as pd

def load_modified_dataset():
    dataset = load_dataset("databricks/databricks-dolly-15k", split = "train")
    df = dataset.to_pandas()
    df['keep'] = True
    
    # Keep entries with correct answer as well
    df = df[(df['category'].isin(['closed_qa', 'information_extraction', 'open_qa'])) & df['keep']]
    
    return Dataset.from_pandas(
        df[['instruction', 'context', 'response']], 
        preserve_index = False)
    
dataset = load_modified_dataset()
# dataset = dataset.select(range(200))

def format_instruction(sample : Dict) -> str:
    """Combine a row to a single str"""
    return f"""### Context:
{sample['context']}

### Question:
Using only the context above, {sample['instruction']}

### Response:
{sample['response']}
"""

import torch
from transformers import AutoTokenizer, AutoModelForCausalLM, BitsAndBytesConfig
from peft import AutoPeftModelForCausalLM
# Hugging Face Base Model ID
model_id = "mistralai/Mistral-7B-v0.1"
is_peft = False

bnb_config = BitsAndBytesConfig(
    load_in_4bit=True,
    bnb_4bit_use_double_quant=False,
    bnb_4bit_quant_type="nf4",
    bnb_4bit_compute_dtype=torch.bfloat16
)

if is_peft:
    # load base LLM model with PEFT Adapter
    model = AutoPeftModelForCausalLM.from_pretrained(
        model_id,
        low_cpu_mem_usage=True,
        torch_dtype=torch.float16,
        use_flash_attention_2=True,
        quantization_config = bnb_config
    )
else:
    
    model = AutoModelForCausalLM.from_pretrained(
        model_id,
        low_cpu_mem_usage=True,
        torch_dtype=torch.float16,
        quantization_config = bnb_config,
        use_flash_attention_2=True
    )

model.config.pretraining_tp = 1

tokenizer = AutoTokenizer.from_pretrained(model_id)
tokenizer.pad_token = tokenizer.eos_token
tokenizer.padding_side = "right"

from peft import LoraConfig, prepare_model_for_kbit_training, get_peft_model

if is_peft:
    model = prepare_model_for_kbit_training(model)
    model._mark_only_adapters_as_trainable()
else:
    # LoRA config for QLoRA
    peft_config = LoraConfig(
        lora_alpha=16,
        lora_dropout=0.1,
        r=8,
        bias="none",
        task_type="CAUSAL_LM",
        target_modules=['v_proj', 'down_proj', 'up_proj', 'o_proj', 'q_proj', 'gate_proj', 'k_proj']
    )

    # prepare model for training with low-precision
    model = prepare_model_for_kbit_training(model)
    model = get_peft_model(model, peft_config)

    from transformers import TrainingArguments
from trl import SFTTrainer

args = TrainingArguments(
    output_dir="./mistral-7b-int4-dolly", 
    num_train_epochs=3, # number of training epochs
    per_device_train_batch_size=16, # batch size per batch
    gradient_accumulation_steps=4, # effective batch size
    gradient_checkpointing=True, 
    gradient_checkpointing_kwargs={'use_reentrant':True},
    optim="paged_adamw_32bit",
    logging_steps=1, # log the training error every 10 steps
    save_strategy="steps",
    save_total_limit = 2, # save 2 total checkpoints
    ignore_data_skip=True,
    save_steps=2, # save a checkpoint every 1 steps
    learning_rate=1e-3,
    bf16=True,
    tf32=True,
    max_grad_norm=1.0,
    warmup_steps=100,
    lr_scheduler_type="constant",
    disable_tqdm=True
)

# https://huggingface.co/docs/trl/sft_trainer#packing-dataset--constantlengthdataset-
# max seq length for packing
max_seq_length = 2048 
trainer = SFTTrainer(
    model=model,
    train_dataset=dataset,
    tokenizer=tokenizer,
    max_seq_length=max_seq_length,
    packing=True,
    formatting_func=format_instruction, # our formatting function which takes a dataset row and maps it to str
    args=args,
)

start = time.time()
trainer.train(resume_from_checkpoint=False) # reduce batch size
trainer.save_model()
end = time.time()
print(f"{end - start}s")