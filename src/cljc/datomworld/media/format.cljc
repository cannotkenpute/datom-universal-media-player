(ns datomworld.media.format
  "Pure contracts for the canonical .datom container and legacy readers."
  (:require
    #?(:clj [clojure.edn :as edn]
       :cljs [cljs.reader :as reader]
       :cljd [clojure.edn :as edn])
    [clojure.string :as str]))


(def version 1)
(def datom-magic "DATOM1\r\n")
(def movie-magic "DATMOV1\n")
(def music-magic "DATMUS1\n")
(def header-size 12)
(def maximum-manifest-bytes (* 1024 1024))


(def ^:private manifest-attributes
  #{:datom.media/version
    :datom.media/kind
    :datom.media/codec-mode
    :datom.media/original-name
    :datom.media/original-mime
    :datom.media/payload-bytes
    :datom.media/duration-seconds})


(defn kind-for-type
  [mime-type]
  (case (str/lower-case (or mime-type ""))
    "video/mp4" :video
    "audio/mpeg" :audio
    nil))


(defn- legacy-kind-for-type
  [mime-type]
  (cond
    (str/starts-with? (or mime-type "") "video/") :video
    (str/starts-with? (or mime-type "") "audio/") :audio
    :else nil))


(defn- extension
  [filename]
  (let [name (str/lower-case (or filename ""))
        dot (.lastIndexOf name ".")]
    (when (not (neg? dot))
      (subs name dot))))


(defn conversion-kind
  "Classify an allowed raw conversion input. Empty MIME values are tolerated
   because mobile document providers do not always return one. Contradictory
   MIME and extension values are rejected."
  [filename mime-type]
  (let [extension-kind (case (extension filename)
                         ".mp4" :video
                         ".mp3" :audio
                         nil)
        mime-kind (when-not (str/blank? (or mime-type ""))
                    (kind-for-type mime-type))]
    (when (and extension-kind
               (or (str/blank? (or mime-type ""))
                   (= extension-kind mime-kind)))
      extension-kind)))


(defn signature-kind
  "Classify the bounded prefix of an MP4 or MP3 payload."
  [bytes]
  (cond
    (and (<= 8 (count bytes))
         (= [102 116 121 112] (mapv #(nth bytes %) (range 4 8))))
    :video

    (and (<= 3 (count bytes))
         (= [73 68 51] (mapv #(nth bytes %) (range 3))))
    :audio

    (and (<= 2 (count bytes))
         (= 255 (nth bytes 0))
         (= 224 (bit-and 224 (nth bytes 1))))
    :audio

    :else nil))


(defn extension-for-kind
  [kind]
  (case kind
    (:video :audio) ".datom"
    :movie ".datmov"
    :music ".datmus"
    nil))


(defn magic-for-kind
  [kind]
  (case kind
    (:video :audio) datom-magic
    :movie movie-magic
    :music music-magic
    nil))


(defn container-for-magic
  [magic]
  (case magic
    "DATOM1\r\n" :datom
    "DATMOV1\n" :datmov
    "DATMUS1\n" :datmus
    nil))


(defn manifest-value
  [datoms attribute]
  (some (fn [[_ attr value _ _]]
          (when (= attr attribute) value))
        datoms))


(defn manifest-datoms
  [{:keys [media/name media/type media/size media/duration-seconds]}]
  (let [kind (conversion-kind name type)
        mime (case kind
               :video "video/mp4"
               :audio "audio/mpeg"
               type)
        facts [[:datom.media/version version]
               [:datom.media/kind kind]
               [:datom.media/codec-mode :native-payload]
               [:datom.media/original-name name]
               [:datom.media/original-mime mime]
               [:datom.media/payload-bytes size]]
        facts (cond-> facts
                (number? duration-seconds)
                (conj [:datom.media/duration-seconds
                       (double duration-seconds)]))]
    (mapv (fn [[attribute value]]
            [-1025 attribute value 1 1])
          facts)))


(defn- canonical-datoms?
  [datoms]
  (and
    (vector? datoms)
    (every? (fn [datom]
              (and (vector? datom)
                   (= 5 (count datom))
                   (= -1025 (nth datom 0))
                   (contains? manifest-attributes (nth datom 1))
                   (= 1 (nth datom 3))
                   (= 1 (nth datom 4))))
            datoms)
    (= (count datoms)
       (count (set (map second datoms))))))


(defn valid-manifest?
  [datoms]
  (and
    (canonical-datoms? datoms)
    (= version (manifest-value datoms :datom.media/version))
    (contains? #{:video :audio}
               (manifest-value datoms :datom.media/kind))
    (= :native-payload
       (manifest-value datoms :datom.media/codec-mode))
    (string? (manifest-value datoms :datom.media/original-name))
    (let [mime (manifest-value datoms :datom.media/original-mime)
          kind (manifest-value datoms :datom.media/kind)]
      (and (string? mime)
           (= kind (kind-for-type mime))
           (= kind
              (conversion-kind
                (manifest-value datoms :datom.media/original-name)
                mime))))
    (let [size (manifest-value datoms :datom.media/payload-bytes)]
      (and (integer? size) (not (neg? size))))))


(defn legacy-valid-manifest?
  [container datoms]
  (and
    (contains? #{:datmov :datmus} container)
    (canonical-datoms? datoms)
    (= version (manifest-value datoms :datom.media/version))
    (= :native-payload
       (manifest-value datoms :datom.media/codec-mode))
    (string? (manifest-value datoms :datom.media/original-name))
    (let [legacy-kind (manifest-value datoms :datom.media/kind)
          mime (manifest-value datoms :datom.media/original-mime)
          expected-kind (case container :datmov :movie :datmus :music)]
      (and (= expected-kind legacy-kind)
           (string? mime)
           (= (case legacy-kind :movie :video :music :audio)
              (legacy-kind-for-type mime))))
    (let [size (manifest-value datoms :datom.media/payload-bytes)]
      (and (integer? size) (not (neg? size))))))


(defn encode-manifest
  [datoms]
  (pr-str datoms))


(defn decode-manifest
  [text]
  (try
    #?(:cljs (reader/read-string text)
       :default (edn/read-string text))
    (catch #?(:clj Exception :cljs :default :cljd Object) _
      nil)))


(defn manifest->metadata
  [datoms]
  (when (valid-manifest? datoms)
    {:media/name
     (manifest-value datoms :datom.media/original-name)
     :media/type
     (manifest-value datoms :datom.media/original-mime)
     :media/size
     (manifest-value datoms :datom.media/payload-bytes)
     :media/kind
     (manifest-value datoms :datom.media/kind)
     :media/container :datom
     :media/format-version version}))


(defn legacy-manifest->metadata
  [container datoms]
  (when (legacy-valid-manifest? container datoms)
    {:media/name
     (manifest-value datoms :datom.media/original-name)
     :media/type
     (manifest-value datoms :datom.media/original-mime)
     :media/size
     (manifest-value datoms :datom.media/payload-bytes)
     :media/kind
     (case container :datmov :video :datmus :audio)
     :media/container container
     :media/format-version version}))
