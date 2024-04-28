from datasets import load_dataset, Dataset
import pandas as pd
import torch
from transformers import TrainingArguments, AutoTokenizer, AutoModelForCausalLM, BitsAndBytesConfig
from trl import SFTTrainer
from peft import prepare_model_for_kbit_training, LoraConfig, get_peft_model
from accelerate import Accelerator
import time
from typing import Dict

def load_modified_dataset():
    dataset = load_dataset("databricks/databricks-dolly-15k", split="train")
    df = dataset.to_pandas()
    df["keep"] = True
    df = df[
        (df["category"].isin(["closed_qa", "information_extraction", "open_qa"]))
        & df["keep"]
    ]
    return Dataset.from_pandas(
        df[["instruction", "context", "response"]], preserve_index=False
    )

def format_instruction(sample: Dict) -> str:
    return f"""### Context:
{sample['context']}

### Question:
Using only the context above, {sample['instruction']}

### Response:
{sample['response']}
"""

def train_model(model_id="mistralai/Mistral-7B-v0.1", output_dir="mistral-7b-int4", resume_from_checkpoint=False, num_train_epochs=1):
    accelerator = Accelerator()
    dataset = load_modified_dataset()



    # load in 4bit
    model = AutoModelForCausalLM.from_pretrained(   
        model_id,
        attn_implementation="flash_attention_2",
    )
    peft_config = LoraConfig(
        lora_alpha=16,
        lora_dropout=0.1,
        r=8,
        inference_mode=False,
        bias="none",
        task_type="CAUSAL_LM",
        target_modules=[
            "v_proj",
            "down_proj",
            "up_proj",
            "o_proj",
            "q_proj",
            "gate_proj",
            "k_proj",
        ],
    )
    model = get_peft_model(model, peft_config)
    model.print_trainable_parameters()
    

    tokenizer = AutoTokenizer.from_pretrained(model_id)
    tokenizer.pad_token = tokenizer.eos_token
    tokenizer.padding_side = "right"

    args = TrainingArguments(
        num_train_epochs=num_train_epochs,
        per_device_train_batch_size=5,
        gradient_accumulation_steps=2,
        gradient_checkpointing=True,
        learning_rate=5e-5,
        lr_scheduler_type="cosine",
        max_steps=200,
        save_strategy="no",
        logging_steps=1,
        output_dir='peft_instruction_tuned',
        optim="paged_adamw_32bit",
        warmup_steps=100,
        bf16=True,
        )

    max_seq_length = 2048
    trainer = SFTTrainer(
        model=model,
        train_dataset=dataset,
        tokenizer=tokenizer,
        max_seq_length=max_seq_length,
        packing=True,
        formatting_func=format_instruction,
        args=args,
    )


    trainer.train(resume_from_checkpoint=resume_from_checkpoint)
    trainer.save_model()

    # Flush memory
# del dpo_trainer, model, ref_model
# gc.collect()
# torch.cuda.empty_cache()

# # Reload model in FP16 (instead of NF4)
# base_model = AutoModelForCausalLM.from_pretrained(
#     model_name,
#     return_dict=True,
#     torch_dtype=torch.float16,
# )
# tokenizer = AutoTokenizer.from_pretrained(model_name)

# # Merge base model with the adapter
# model = PeftModel.from_pretrained(base_model, "final_checkpoint")
# model = model.merge_and_unload()

# # Save model and tokenizer
# model.save_pretrained(new_model)
# tokenizer.save_pretrained(new_model)


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--model_id", type=str, default="mistralai/Mistral-7B-v0.1", help="base model to fine tune")
    parser.add_argument("--output_dir", type=str, default="mistral-7b-int4", help="output directory")
    parser.add_argument("--num_train_epochs", type=int, default=1, help="number of training epochs")
    parser.add_argument("--resume_from_checkpoint", action="store_true", help="resume training from latest checkpoint")
    args = parser.parse_args()
    train_model(
        model_id=args.model_id,
        output_dir=args.output_dir,
        num_train_epochs=args.num_train_epochs,
        resume_from_checkpoint=args.resume_from_checkpoint,
    )
