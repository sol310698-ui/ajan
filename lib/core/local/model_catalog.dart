/// Uygulamadan indirilebilecek yerel (offline) yapay zeka modelleri.
///
/// GGUF (llama.cpp uyumlu, int4) formatinda; hepsi HuggingFace uzerinden
/// acik ve token'siz indirilebilir. Kucuk + int4 secildi ki telefon donmasin.
class LocalModelInfo {
  final String id;
  final String name;
  final int sizeMb;
  final String description;
  final String url;
  final String fileName;

  const LocalModelInfo({
    required this.id,
    required this.name,
    required this.sizeMb,
    required this.description,
    required this.url,
    required this.fileName,
  });
}

const List<LocalModelInfo> kModelCatalog = [
  LocalModelInfo(
    id: 'llama32-1b',
    name: 'Llama 3.2 1B (int4)',
    sizeMb: 808,
    description: 'En hafif ve hizli. Dusuk kaynak; sohbet ve basit gorevler. '
        'Onerilen baslangic.',
    url:
        'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
    fileName: 'llama-3.2-1b-q4.gguf',
  ),
  LocalModelInfo(
    id: 'gemma2-2b',
    name: 'Gemma 2 2B (int4)',
    sizeMb: 1710,
    description: 'Dengeli: daha iyi akil, hala makul kaynak. 4GB+ RAM iyi olur.',
    url:
        'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf',
    fileName: 'gemma-2-2b-q4.gguf',
  ),
  LocalModelInfo(
    id: 'llama32-3b',
    name: 'Llama 3.2 3B (int4)',
    sizeMb: 2020,
    description: 'Daha guclu akil; 6GB+ RAM ister, dusuk cihazlarda zorlar.',
    url:
        'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
    fileName: 'llama-3.2-3b-q4.gguf',
  ),
  LocalModelInfo(
    id: 'phi35-mini',
    name: 'Phi-3.5 mini (int4)',
    sizeMb: 2390,
    description: 'Guclu; kod/akil iyi ama en agiri. 6GB+ RAM.',
    url:
        'https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf',
    fileName: 'phi-3.5-mini-q4.gguf',
  ),
];
