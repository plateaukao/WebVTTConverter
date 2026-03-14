import Foundation

let languageMap: [String: String] = [
    "en": "English",
    "ja": "Japanese",
    "zh-Hant": "Traditional Chinese",
    "ko": "Korean",
    "en-GB": "English GB",
    "fr": "French",
    "zh-Hans": "Simplified Chinese",
    "es": "Spanish",
    "de": "German",
    "it": "Italian",
    "pt": "Portuguese",
    "ru": "Russian",
    "ar": "Arabic",
    "hi": "Hindi",
    "th": "Thai",
    "vi": "Vietnamese",
    "id": "Indonesian",
    "ms": "Malay",
    "pl": "Polish",
    "nl": "Dutch",
    "sv": "Swedish",
    "da": "Danish",
    "no": "Norwegian",
    "fi": "Finnish",
    "tr": "Turkish",
    "he": "Hebrew",
    "el": "Greek",
    "cs": "Czech",
    "hu": "Hungarian",
    "ro": "Romanian",
    "uk": "Ukrainian",
]

func longLanguageName(for shortName: String) -> String {
    if shortName.hasSuffix("[cc]") {
        let name = String(shortName.dropLast(4))
        return (languageMap[name] ?? name) + "[cc]"
    }
    return languageMap[shortName] ?? shortName
}
