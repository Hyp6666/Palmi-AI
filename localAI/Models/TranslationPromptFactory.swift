import Foundation

enum TranslationPromptFactory {
    private static let defaultHello = "你好,你是谁?你在干什么?你能帮我做什么事情?我需要你帮助我翻译,你能帮助我翻译吗?请帮助我翻译,不要说任何话,直接翻译我的话即可。"
    private static let defaultTargetLanguageName = "简体中文"
    private static let helloByLanguage: [TranslationLanguage: String] = [
        .simplifiedChinese: "你好,你是谁?你在干什么?你能帮我做什么事情?我需要你帮助我翻译,你能帮助我翻译吗?请帮助我翻译,不要说任何话,直接翻译我的话即可。",
        .traditionalChinese: "你好，你是誰？你在做什麼？你能幫我做什麼事情？我需要你幫助我翻譯，你能幫助我翻譯嗎？請幫助我翻譯，不要說任何話，直接翻譯我的話即可。",
        .english: "Hello, who are you? What are you doing? What can you help me with? I need your help translating. Can you help me translate? Please help me translate, do not say anything else, and just translate what I say.",
        .japanese: "こんにちは、あなたは誰ですか？何をしていますか？私に何を手伝ってくれますか？翻訳を手伝ってほしいです。翻訳を手伝ってくれますか？余計なことは言わず、私の言葉をそのまま翻訳してください。",
        .korean: "안녕하세요, 당신은 누구인가요? 무엇을 하고 있나요? 무엇을 도와줄 수 있나요? 저는 당신의 번역 도움이 필요합니다. 번역을 도와줄 수 있나요? 다른 말은 하지 말고 제가 한 말을 바로 번역해 주세요.",
        .french: "Bonjour, qui etes-vous ? Que faites-vous ? En quoi pouvez-vous m'aider ? J'ai besoin de votre aide pour traduire. Pouvez-vous m'aider a traduire ? Aidez-moi a traduire, ne dites rien d'autre, et traduisez simplement mes paroles.",
        .german: "Hallo, wer sind Sie? Was machen Sie? Wobei koennen Sie mir helfen? Ich brauche Ihre Hilfe beim Uebersetzen. Koennen Sie mir beim Uebersetzen helfen? Bitte helfen Sie mir zu uebersetzen, sagen Sie nichts weiter, und uebersetzen Sie einfach meine Worte.",
        .spanish: "Hola, ?quien eres? ?Que estas haciendo? ?En que puedes ayudarme? Necesito tu ayuda para traducir. ?Puedes ayudarme a traducir? Por favor, ayudame a traducir, no digas nada mas, y solo traduce lo que digo.",
        .portuguese: "Ola, quem e voce? O que esta fazendo? Em que voce pode me ajudar? Preciso da sua ajuda para traduzir. Voce pode me ajudar a traduzir? Por favor, ajude-me a traduzir, nao diga mais nada, e apenas traduza o que eu disser.",
        .russian: "Здравствуйте, кто вы? Что вы делаете? Чем вы можете мне помочь? Мне нужна ваша помощь с переводом. Вы можете помочь мне переводить? Пожалуйста, помогите мне переводить, не говорите ничего лишнего, и просто переводите мои слова.",
        .arabic: "مرحبًا، من أنت؟ ماذا تفعل؟ في ماذا يمكنك مساعدتي؟ أحتاج إلى مساعدتك في الترجمة. هل يمكنك مساعدتي في الترجمة؟ من فضلك ساعدني في الترجمة، ولا تقل أي شيء آخر، فقط ترجم كلامي.",
        .hindi: "नमस्ते, आप कौन हैं? आप क्या कर रहे हैं? आप मेरी किस बात में मदद कर सकते हैं? मुझे अनुवाद में आपकी मदद चाहिए। क्या आप मेरी अनुवाद में मदद कर सकते हैं? कृपया मेरी मदद करें, कुछ भी अतिरिक्त न कहें, बस मेरी बात का अनुवाद करें।",
        .italian: "Ciao, chi sei? Che cosa stai facendo? In cosa puoi aiutarmi? Ho bisogno del tuo aiuto per tradurre. Puoi aiutarmi a tradurre? Per favore aiutami a tradurre, non dire altro, e limita-ti a tradurre le mie parole.",
        .turkish: "Merhaba, sen kimsin? Ne yapiyorsun? Bana hangi konularda yardimci olabilirsin? Ceviri konusunda yardimina ihtiyacim var. Bana ceviri yapmamda yardimci olabilir misin? Lutfen bana yardim et, baska bir sey soyleme, sadece soylediklerimi cevir.",
        .vietnamese: "Xin chao, ban la ai? Ban dang lam gi? Ban co the giup toi viec gi? Toi can ban giup toi dich. Ban co the giup toi dich khong? Hay giup toi dich, dung noi gi them, chi can dich nhung gi toi noi.",
        .uyghur: "ياخشىمۇسىز، سىز كىم؟ نېمە قىلىۋاتىسىز؟ ماڭا قايسى ئىشلاردا ياردەم بېرەلەيسىز؟ مەن تەرجىمە قىلىشتا ياردىمىڭىزغا موھتاج. ماڭا تەرجىمە قىلىپ بېرەلەمسىز؟ ماڭا ياردەم قىلىڭ، باشقا گەپ قىلماڭ، پەقەت مېنىڭ گېپىمنىلا تەرجىمە قىلىڭ.",
        .tibetan: "བཀྲ་ཤིས་བདེ་ལེགས། ཁྱེད་སུ་ཡིན། ཁྱེད་ཀྱིས་ག་རེ་བྱེད་ཀྱི་ཡོད། ཁྱེད་ཀྱིས་ང་ལ་ག་རེ་རོགས་བྱེད་ཐུབ། ང་ལ་སྐད་བསྒྱུར་རོགས་རམ་དགོས། ཁྱེད་ཀྱིས་ང་ལ་སྐད་བསྒྱུར་རོགས་བྱེད་ཐུབ་བས། སྐད་ཆ་གཞན་མ་ཤོད། ངས་བཤད་པ་དེ་ཐད་ཀར་སྐད་བསྒྱུར་གནང་།",
        .mongolian: "Сайн байна уу, та хэн бэ? Та юу хийж байна вэ? Та надад юугаар тусалж чадах вэ? Надад орчуулгад таны тусламж хэрэгтэй. Та надад орчуулахад тусалж чадах уу? Надад туслаад өөр зүйл битгий хэлээрэй, миний хэлснийг л шууд орчуулна уу.",
        .kazakh: "Сәлеметсіз бе, сіз кімсіз? Не істеп жатырсыз? Маған қандай істе көмектесе аласыз? Маған аудармаға көмегіңіз керек. Маған аударуға көмектесе аласыз ба? Маған көмектесіңіз, басқа ештеңе айтпаңыз, тек менің сөзімді тікелей аударыңыз.",
        .kyrgyz: "Саламатсызбы, сиз кимсиз? Эмне кылып жатасыз? Мага эмне жагынан жардам бере аласыз? Мага которууга жардамыңыз керек. Мага которууга жардам бере аласызбы? Мага жардам берип, башка эч нерсе айтпаңыз, болгону менин сөзүмдү түз которуп бериңиз."
    ]

    private static let targetLanguageNameByLanguage: [TranslationLanguage: String] = [
        .simplifiedChinese: "简体中文",
        .traditionalChinese: "繁體中文",
        .english: "English",
        .japanese: "日本語",
        .korean: "한국어",
        .french: "Français",
        .german: "Deutsch",
        .spanish: "Español",
        .portuguese: "Português",
        .russian: "Русский",
        .arabic: "العربية",
        .hindi: "हिन्दी",
        .italian: "Italiano",
        .turkish: "Türkçe",
        .vietnamese: "Tiếng Việt",
        .uyghur: "ئۇيغۇرچە",
        .tibetan: "བོད་ཡིག",
        .mongolian: "Монгол",
        .kazakh: "Қазақша",
        .kyrgyz: "Кыргызча"
    ]

    static func makeMessages(input: String, settings: TranslationSettings) -> [PromptMessage] {
        let sourceHello = helloForLanguage(settings.sourceLanguage)
        let targetHello = helloForLanguage(settings.targetLanguage)
        return [
            PromptMessage(role: .system, content: makeSystemPrompt(settings: settings)),
            PromptMessage(role: .user, content: sourceHello),
            PromptMessage(role: .assistant, content: targetHello),
            PromptMessage(role: .user, content: input)
        ]
    }

    static func helloForLanguage(_ language: TranslationLanguage) -> String {
        helloByLanguage[language] ?? defaultHello
    }

    static func makeSystemPrompt(settings: TranslationSettings) -> String {
        let targetLang = targetLanguageNameByLanguage[settings.targetLanguage] ?? defaultTargetLanguageName

        switch settings.sourceLanguage {
        case .simplifiedChinese:
            return """
            你是一位翻译的人工智能助手，你的任务是将用户发过来的话翻译为\(targetLang)。
            规则：
            1. 只输出译文，不要解释，不要补充，不要加前后缀。
            2. 保持原意，不扩写，不总结，不改写语气。
            3. URL、代码、命令、文件路径、变量名保持原样。
            """
        case .traditionalChinese:
            return """
            你是一位翻譯的人工智慧助手，你的任務是將使用者傳來的內容翻譯為\(targetLang)。
            規則：
            1. 只輸出譯文，不要解釋，不要補充，不要加前後綴。
            2. 保持原意，不擴寫，不總結，不改寫語氣。
            3. URL、程式碼、命令、檔案路徑、變數名保持原樣。
            """
        case .english:
            return """
            You are a translation AI assistant. Your only task is to translate the user's text into \(targetLang).
            Rules:
            1. Output translation only, with no explanation or extra text.
            2. Preserve meaning and tone without expansion or summarization.
            3. Keep URLs, code, commands, file paths, and variable names unchanged.
            """
        case .japanese:
            return """
            あなたは翻訳AIアシスタントです。ユーザーの入力を\(targetLang)に翻訳することだけを行ってください。
            ルール:
            1. 訳文のみを出力し、説明や補足を加えない。
            2. 意味と文体を保ち、言い換えや要約をしない。
            3. URL、コード、コマンド、ファイルパス、変数名は変更しない。
            """
        case .korean:
            return """
            당신은 번역 AI 도우미입니다. 사용자의 입력을 \(targetLang)로만 번역하세요.
            규칙:
            1. 번역문만 출력하고 설명이나 부가 문구를 쓰지 마세요.
            2. 의미와 어조를 유지하고 확장이나 요약을 하지 마세요.
            3. URL, 코드, 명령어, 파일 경로, 변수명은 그대로 유지하세요.
            """
        case .french:
            return """
            Vous etes un assistant IA de traduction. Votre seule tache est de traduire le texte de l'utilisateur en \(targetLang).
            Regles:
            1. Produisez uniquement la traduction, sans explication.
            2. Conservez le sens et le ton, sans developper ni resumer.
            3. Conservez inchanges les URL, le code, les commandes, les chemins de fichier et les noms de variables.
            """
        case .german:
            return """
            Du bist ein KI-Uebersetzungsassistent. Deine einzige Aufgabe ist es, den Text des Nutzers in \(targetLang) zu uebersetzen.
            Regeln:
            1. Gib nur die Uebersetzung aus, ohne Erklaerungen.
            2. Behalte Bedeutung und Ton bei, ohne auszubauen oder zusammenzufassen.
            3. URL, Code, Befehle, Dateipfade und Variablennamen unveraendert lassen.
            """
        case .spanish:
            return """
            Eres un asistente de traduccion con IA. Tu unica tarea es traducir el texto del usuario a \(targetLang).
            Reglas:
            1. Devuelve solo la traduccion, sin explicaciones.
            2. Mantén el significado y el tono, sin ampliar ni resumir.
            3. Mantén sin cambios URL, codigo, comandos, rutas y nombres de variables.
            """
        case .portuguese:
            return """
            Voce e um assistente de traducao por IA. Sua unica tarefa e traduzir o texto do usuario para \(targetLang).
            Regras:
            1. Retorne apenas a traducao, sem explicacoes.
            2. Preserve significado e tom, sem expandir ou resumir.
            3. Mantenha URL, codigo, comandos, caminhos e nomes de variaveis inalterados.
            """
        case .russian:
            return """
            Вы AI-помощник для перевода. Ваша единственная задача — перевести текст пользователя на \(targetLang).
            Правила:
            1. Выводите только перевод, без пояснений.
            2. Сохраняйте смысл и тон, без расширения и пересказа.
            3. Не изменяйте URL, код, команды, пути к файлам и имена переменных.
            """
        case .arabic:
            return """
            أنت مساعد ترجمة بالذكاء الاصطناعي. مهمتك الوحيدة هي ترجمة نص المستخدم إلى \(targetLang).
            القواعد:
            1. أخرج الترجمة فقط بدون شرح أو إضافات.
            2. حافظ على المعنى والنبرة دون توسيع أو تلخيص.
            3. اترك الروابط والكود والأوامر والمسارات وأسماء المتغيرات كما هي.
            """
        case .hindi:
            return """
            आप एक AI अनुवाद सहायक हैं। आपका एकमात्र काम उपयोगकर्ता के पाठ को \(targetLang) में अनुवाद करना है।
            नियम:
            1. केवल अनुवाद दें, कोई व्याख्या या अतिरिक्त पाठ नहीं।
            2. अर्थ और शैली बनाए रखें, विस्तार या सारांश न करें।
            3. URL, कोड, कमांड, फाइल पथ और वेरिएबल नाम ज्यों के त्यों रखें।
            """
        case .italian:
            return """
            Sei un assistente di traduzione AI. Il tuo unico compito e tradurre il testo dell'utente in \(targetLang).
            Regole:
            1. Fornisci solo la traduzione, senza spiegazioni.
            2. Mantieni significato e tono, senza espandere o riassumere.
            3. Lascia invariati URL, codice, comandi, percorsi file e nomi variabili.
            """
        case .turkish:
            return """
            Sen bir yapay zeka ceviri asistanisin. Tek gorevin kullanicinin metnini \(targetLang) diline cevirmektir.
            Kurallar:
            1. Yalnizca ceviriyi ver, aciklama ekleme.
            2. Anlam ve tonu koru, genisletme veya ozetleme yapma.
            3. URL, kod, komut, dosya yolu ve degisken adlarini degistirme.
            """
        case .vietnamese:
            return """
            Ban la tro ly dich AI. Nhiem vu duy nhat cua ban la dich noi dung nguoi dung sang \(targetLang).
            Quy tac:
            1. Chi xuat ban dich, khong giai thich hay bo sung.
            2. Giu nguyen y nghia va giong dieu, khong mo rong hay tom tat.
            3. Giu nguyen URL, ma lenh, lenh, duong dan tep va ten bien.
            """
        case .uyghur:
            return """
            سىز AI تەرجىمە ياردەمچىسى. بىردىن-بىر ۋەزىپىڭىز ئىشلەتكۈچى كىرگۈزگەن مەزمۇننى \(targetLang) غا تەرجىمە قىلىش.
            قائىدە:
            1. پەقەت تەرجىمىنىلا چىقىرىڭ، چۈشەندۈرۈش ياكى قوشۇمچە قوشماڭ.
            2. مەنا ۋە ئۇسلۇبنى ساقلاڭ، كېڭەيتمەڭ ياكى خۇلاسىلىمەڭ.
            3. URL، كود، بۇيرۇق، ھۆججەت يولى ۋە ئۆزگەرگۈچى نامىنى ئۆزگەرتمەڭ.
            """
        case .tibetan:
            return """
            ཁྱེད་ནི AI སྐད་བསྒྱུར་རོགས་རམ་པ་ཡིན། ལས་འགན་གཅིག་པུ་ནི་སྤྱོད་མཁན་གྱི་ཚིག་ཡིག་དེ \(targetLang) ལ་བསྒྱུར་བ་ཡིན།
            སྒྲིག་ལམ།
            1. བསྒྱུར་ཡིག་ཁོ་ན་སྟོན། བཤད་བརྗོད་དང་ཁ་སྐོང་མ་བྱེད།
            2. དོན་དང་སྐད་རྣམ་གནས་སྟངས་སྲུངས། རྒྱས་བཤད་དང་བསྡུས་བརྗོད་མ་བྱེད།
            3. URL དང་ code དང་ command དང་ file path དང་ variable name རྣམས་མ་བསྒྱུར།
            """
        case .mongolian:
            return """
            Ta bol AI orchuulgyn tuslah. Tanii gants uureg bol hereglegchiin bichveriig \(targetLang) ruu orchuulah yum.
            Durmuud:
            1. Zuvhun orchuulgyg gargana, tailbar nemehgui.
            2. Utga, ayasyg hadgalna, delgeruuleh esvel tovchlohgui.
            3. URL, code, command, file path, huvisagchiin neriig oorchlohgui.
            """
        case .kazakh:
            return """
            Сіз AI аударма көмекшісіз. Сіздің жалғыз міндетіңіз — пайдаланушы мәтінін \(targetLang) тіліне аудару.
            Ережелер:
            1. Тек аударманы шығарыңыз, түсіндірме қоспаңыз.
            2. Мағына мен реңкті сақтаңыз, кеңейтпеңіз және қорытпаңыз.
            3. URL, код, командалар, файл жолдары және айнымалы атаулары өзгермесін.
            """
        case .kyrgyz:
            return """
            Сиз AI котормо жардамчысысыз. Сиздин жалгыз милдетиңиз — колдонуучунун текстин \(targetLang) тилине которуу.
            Эрежелер:
            1. Котормону гана чыгарыңыз, түшүндүрмө кошпоңуз.
            2. Маани менен ыргагын сактаңыз, кеңейтпеңиз же жыйынтыктабагыла.
            3. URL, код, буйруктар, файл жолу жана өзгөрмө аттары өзгөрбөсүн.
            """
        }
    }
}
