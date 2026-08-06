(ns datomworld.media.format-test
  (:require
    [clojure.test :refer [deftest is testing]]
    [datomworld.media.format :as media-format]))


(deftest datom-manifest-is-canonical-d5-test
  (let [datoms (media-format/manifest-datoms
                 {:media/name "clip.mp4"
                  :media/type "video/mp4"
                  :media/size 4096
                  :media/duration-seconds 12.5})]
    (is (every? #(= 5 (count %)) datoms))
    (is (every? #(= -1025 (first %)) datoms))
    (is (= :video
           (media-format/manifest-value datoms :datom.media/kind)))
    (is (= :native-payload
           (media-format/manifest-value
             datoms :datom.media/codec-mode)))
    (is (= ".datom" (media-format/extension-for-kind :video)))
    (is (= media-format/datom-magic
           (media-format/magic-for-kind :video)))))


(deftest audio-manifest-round-trips-through-edn-test
  (let [datoms (media-format/manifest-datoms
                 {:media/name "track.mp3"
                  :media/type "audio/mpeg"
                  :media/size 8192})
        encoded (media-format/encode-manifest datoms)
        decoded (media-format/decode-manifest encoded)]
    (is (= datoms decoded))
    (is (media-format/valid-manifest? decoded))
    (is (= {:media/name "track.mp3"
            :media/type "audio/mpeg"
            :media/size 8192
            :media/kind :audio
            :media/container :datom
            :media/format-version 1}
           (media-format/manifest->metadata decoded)))))


(deftest conversion-input-is-restricted-to-mp4-and-mp3-test
  (is (= :video
         (media-format/conversion-kind "clip.mp4" "video/mp4")))
  (is (= :audio
         (media-format/conversion-kind "track.mp3" "audio/mpeg")))
  (is (nil? (media-format/conversion-kind "track.flac" "audio/flac")))
  (is (nil? (media-format/conversion-kind "clip.mp4" "audio/mpeg")))
  (is (nil? (media-format/conversion-kind "renamed.datom" "video/mp4"))))


(deftest native-signatures-are-validated-test
  (testing "MP4 ftyp box"
    (is (= :video
           (media-format/signature-kind
             [0 0 0 24 102 116 121 112 105 115 111 109]))))
  (testing "MP3 ID3 and MPEG frame sync"
    (is (= :audio (media-format/signature-kind [73 68 51 4 0 0])))
    (is (= :audio (media-format/signature-kind [255 251 144 100]))))
  (is (nil? (media-format/signature-kind [0 1 2 3 4 5 6 7]))))


(deftest legacy-manifests-remain-readable-test
  (doseq [[legacy-kind expected-kind expected-container]
          [[:movie :video :datmov]
           [:music :audio :datmus]]]
    (let [mime (if (= legacy-kind :movie) "video/mp4" "audio/mpeg")
          datoms [[-1025 :datom.media/version 1 1 1]
                  [-1025 :datom.media/kind legacy-kind 1 1]
                  [-1025 :datom.media/codec-mode :native-payload 1 1]
                  [-1025 :datom.media/original-name
                   (if (= legacy-kind :movie) "clip.mp4" "track.mp3") 1 1]
                  [-1025 :datom.media/original-mime mime 1 1]
                  [-1025 :datom.media/payload-bytes 10 1 1]]]
      (is (= expected-kind
             (:media/kind
               (media-format/legacy-manifest->metadata
                 expected-container datoms)))))))


(deftest magic-dispatch-does-not-trust-file-extension-test
  (is (= :datom (media-format/container-for-magic
                  media-format/datom-magic)))
  (is (= :datmov (media-format/container-for-magic
                   media-format/movie-magic)))
  (is (= :datmus (media-format/container-for-magic
                   media-format/music-magic)))
  (is (nil? (media-format/container-for-magic "not-mp4!"))))


(deftest malformed-or-inconsistent-manifests-are-rejected-test
  (is (false? (media-format/valid-manifest?
                [[-1025 :datom.media/version 99 1 1]])))
  (is (false? (media-format/valid-manifest?
                [[-1025 :datom.media/version 1 1 0]])))
  (is (false? (media-format/valid-manifest?
                {:not "datoms"})))
  (is (false?
        (media-format/valid-manifest?
          [[-1025 :datom.media/version 1 1 1]
           [-1025 :datom.media/kind :video 1 1]
           [-1025 :datom.media/codec-mode :native-payload 1 1]
           [-1025 :datom.media/original-name "track.mp3" 1 1]
           [-1025 :datom.media/original-mime "audio/mpeg" 1 1]
           [-1025 :datom.media/payload-bytes 10 1 1]]))))
