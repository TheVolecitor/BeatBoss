import 'dart:convert';

import 'package:beatboss/core/services/youtube_service.dart';
import 'package:beatboss/core/services/ytmusic_innertube.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('YtMusicInnerTube.search returns songs before videos plus artists, albums, playlists',
      () async {
    final client = MockClient((req) async {
      expect(req.url.host, 'music.youtube.com');
      expect(req.url.path, '/youtubei/v1/search');
      return http.Response(
        jsonEncode({
          'contents': {
            'tabbedSearchResultsRenderer': {
              'tabs': [
                {
                  'tabRenderer': {
                    'content': {
                      'sectionListRenderer': {
                        'contents': [
                          {
                            'musicShelfRenderer': {
                              'title': {
                                'runs': [
                                  {'text': 'Videos'}
                                ]
                              },
                              'contents': [
                                {
                                  'musicResponsiveListItemRenderer': {
                                    'flexColumns': [
                                      {
                                        'musicResponsiveListItemFlexColumnRenderer': {
                                          'text': {
                                            'runs': [
                                              {'text': 'Let It Happen (Live)'}
                                            ]
                                          }
                                        }
                                      },
                                      {
                                        'musicResponsiveListItemFlexColumnRenderer': {
                                          'text': {
                                            'runs': [
                                              {'text': 'Tame Impala • 4:18'}
                                            ]
                                          }
                                        }
                                      },
                                    ],
                                    'overlay': {
                                      'musicItemThumbnailOverlayRenderer': {
                                        'content': {
                                          'musicPlayButtonRenderer': {
                                            'playNavigationEndpoint': {
                                              'watchEndpoint': {
                                                'videoId': 'vid-1',
                                              }
                                            }
                                          }
                                        }
                                      }
                                    },
                                  }
                                }
                              ]
                            }
                          },
                          {
                            'musicShelfRenderer': {
                              'title': {
                                'runs': [
                                  {'text': 'Songs'}
                                ]
                              },
                              'contents': [
                                {
                                  'musicResponsiveListItemRenderer': {
                                    'flexColumns': [
                                      {
                                        'musicResponsiveListItemFlexColumnRenderer': {
                                          'text': {
                                            'runs': [
                                              {'text': 'Let It Happen'}
                                            ]
                                          }
                                        }
                                      },
                                      {
                                        'musicResponsiveListItemFlexColumnRenderer': {
                                          'text': {
                                            'runs': [
                                              {'text': 'Tame Impala • Currents • 7:47'}
                                            ]
                                          }
                                        }
                                      },
                                    ],
                                    'overlay': {
                                      'musicItemThumbnailOverlayRenderer': {
                                        'content': {
                                          'musicPlayButtonRenderer': {
                                            'playNavigationEndpoint': {
                                              'watchEndpoint': {
                                                'videoId': 'song-1',
                                              }
                                            }
                                          }
                                        }
                                      }
                                    },
                                  }
                                }
                              ]
                            }
                          },
                          {
                            'musicShelfRenderer': {
                              'title': {
                                'runs': [
                                  {'text': 'Artists'}
                                ]
                              },
                              'contents': [
                                {
                                  'musicResponsiveListItemRenderer': {
                                    'flexColumns': [
                                      {
                                        'musicResponsiveListItemFlexColumnRenderer': {
                                          'text': {
                                            'runs': [
                                              {'text': 'Tame Impala'}
                                            ]
                                          }
                                        }
                                      },
                                    ],
                                    'navigationEndpoint': {
                                      'browseEndpoint': {
                                        'browseId': 'UC_tame',
                                        'browseEndpointContextSupportedConfigs': {
                                          'browseEndpointContextMusicConfig': {
                                            'pageType': 'MUSIC_PAGE_TYPE_ARTIST',
                                          }
                                        }
                                      }
                                    },
                                  }
                                }
                              ]
                            }
                          },
                          {
                            'musicShelfRenderer': {
                              'title': {
                                'runs': [
                                  {'text': 'Albums'}
                                ]
                              },
                              'contents': [
                                {
                                  'musicResponsiveListItemRenderer': {
                                    'flexColumns': [
                                      {
                                        'musicResponsiveListItemFlexColumnRenderer': {
                                          'text': {
                                            'runs': [
                                              {'text': 'Currents'}
                                            ]
                                          }
                                        }
                                      },
                                      {
                                        'musicResponsiveListItemFlexColumnRenderer': {
                                          'text': {
                                            'runs': [
                                              {'text': 'Album • Tame Impala • 2015'}
                                            ]
                                          }
                                        }
                                      },
                                    ],
                                    'navigationEndpoint': {
                                      'browseEndpoint': {
                                        'browseId': 'MPREb_currents',
                                        'browseEndpointContextSupportedConfigs': {
                                          'browseEndpointContextMusicConfig': {
                                            'pageType': 'MUSIC_PAGE_TYPE_ALBUM',
                                          }
                                        }
                                      }
                                    },
                                  }
                                }
                              ]
                            }
                          },
                          {
                            'musicShelfRenderer': {
                              'title': {
                                'runs': [
                                  {'text': 'Community playlists'}
                                ]
                              },
                              'contents': [
                                {
                                  'musicResponsiveListItemRenderer': {
                                    'flexColumns': [
                                      {
                                        'musicResponsiveListItemFlexColumnRenderer': {
                                          'text': {
                                            'runs': [
                                              {'text': 'Tame Impala Essentials'}
                                            ]
                                          }
                                        }
                                      },
                                    ],
                                    'navigationEndpoint': {
                                      'browseEndpoint': {
                                        'browseId': 'VLPL123',
                                        'browseEndpointContextSupportedConfigs': {
                                          'browseEndpointContextMusicConfig': {
                                            'pageType': 'MUSIC_PAGE_TYPE_PLAYLIST',
                                          }
                                        }
                                      }
                                    },
                                  }
                                }
                              ]
                            }
                          },
                        ]
                      }
                    }
                  }
                }
              ]
            }
          }
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final ytm = YtMusicInnerTube(client: client);
    final result = await ytm.search('Tame Impala', addonId: 'com.beatboss.ytmusic');

    expect(result.tracks.map((t) => t.id), ['song-1', 'vid-1']);
    expect(result.tracks.first.album, 'Currents');
    expect(result.tracks.first.duration, 467);
    expect(result.artists.single.id, 'UC_tame');
    expect(result.albums.single.id, 'MPREb_currents');
    expect(result.albums.single.year, '2015');
    expect(result.playlists.single.id, 'VLPL123');
  });

  test('YouTubeService imports playlists via YtMusicInnerTube with continuation',
      () async {
    var call = 0;
    final client = MockClient((req) async {
      call++;
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      if (call == 1) {
        expect(body['browseId'], 'VLPL_TEST');
        return http.Response(
          jsonEncode({
            'contents': {
              'musicShelfRenderer': {
                'contents': [
                  {
                    'musicResponsiveListItemRenderer': {
                      'flexColumns': [
                        {
                          'musicResponsiveListItemFlexColumnRenderer': {
                            'text': {
                              'runs': [
                                {'text': 'Track One'}
                              ]
                            }
                          }
                        },
                        {
                          'musicResponsiveListItemFlexColumnRenderer': {
                            'text': {
                              'runs': [
                                {'text': 'Artist One'}
                              ]
                            }
                          }
                        },
                      ],
                      'playlistItemData': {'videoId': 'v1'},
                    }
                  }
                ],
                'continuations': [
                  {
                    'nextContinuationData': {'continuation': 'cont-2'}
                  }
                ],
              }
            }
          }),
          200,
        );
      }
      expect(body['continuation'], 'cont-2');
      return http.Response(
        jsonEncode({
          'continuationContents': {
            'musicShelfContinuation': {
              'contents': [
                {
                  'musicResponsiveListItemRenderer': {
                    'flexColumns': [
                      {
                        'musicResponsiveListItemFlexColumnRenderer': {
                          'text': {
                            'runs': [
                              {'text': 'Track Two'}
                            ]
                          }
                        }
                      },
                      {
                        'musicResponsiveListItemFlexColumnRenderer': {
                          'text': {
                            'runs': [
                              {'text': 'Artist Two'}
                            ]
                          }
                        }
                      },
                    ],
                    'playlistItemData': {'videoId': 'v2'},
                  }
                }
              ],
            }
          }
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final yt = YouTubeService(innerTube: YtMusicInnerTube(client: client));
    final items = await yt.getPlaylistTracks(
      'https://music.youtube.com/playlist?list=PL_TEST',
    );

    expect(items.map((i) => i.videoId), ['v1', 'v2']);
    expect(items.map((i) => i.title), ['Track One', 'Track Two']);
    expect(items.map((i) => i.channel), ['Artist One', 'Artist Two']);
  });

  test('YtMusicInnerTube.search parses itemSectionRenderer and upscales thumbnails',
      () async {
    final client = MockClient((req) async {
      return http.Response(
        jsonEncode({
          'contents': {
            'tabbedSearchResultsRenderer': {
              'tabs': [
                {
                  'tabRenderer': {
                    'content': {
                      'sectionListRenderer': {
                        'contents': [
                          {
                            'musicCardShelfRenderer': {
                              'title': {
                                'runs': [
                                  {
                                    'text': 'Top Video',
                                    'navigationEndpoint': {
                                      'watchEndpoint': {'videoId': 'top-vid'}
                                    }
                                  }
                                ]
                              },
                              'subtitle': {
                                'runs': [
                                  {'text': 'Video • Artist • 1M'}
                                ]
                              },
                              'contents': [
                                {
                                  'musicResponsiveListItemRenderer': {
                                    'flexColumns': [
                                      {
                                        'musicResponsiveListItemFlexColumnRenderer': {
                                          'text': {
                                            'runs': [
                                              {'text': 'More From YouTube'}
                                            ]
                                          }
                                        }
                                      },
                                      {
                                        'musicResponsiveListItemFlexColumnRenderer': {
                                          'text': {
                                            'runs': [
                                              {'text': 'Channel • 2:39'}
                                            ]
                                          }
                                        }
                                      },
                                    ],
                                    'overlay': {
                                      'musicItemThumbnailOverlayRenderer': {
                                        'content': {
                                          'musicPlayButtonRenderer': {
                                            'playNavigationEndpoint': {
                                              'watchEndpoint': {'videoId': 'yt-1'}
                                            }
                                          }
                                        }
                                      }
                                    },
                                  }
                                }
                              ]
                            }
                          },
                          {
                            'itemSectionRenderer': {
                              'contents': [
                                {
                                  'musicResponsiveListItemRenderer': {
                                    'thumbnail': {
                                      'musicThumbnailRenderer': {
                                        'thumbnail': {
                                          'thumbnails': [
                                            {
                                              'url':
                                                  'https://lh3.googleusercontent.com/abc=w120-h120-l90-rj'
                                            }
                                          ]
                                        }
                                      }
                                    },
                                    'flexColumns': [
                                      {
                                        'musicResponsiveListItemFlexColumnRenderer': {
                                          'text': {
                                            'runs': [
                                              {'text': 'FREAKED OUT'}
                                            ]
                                          }
                                        }
                                      },
                                      {
                                        'musicResponsiveListItemFlexColumnRenderer': {
                                          'text': {
                                            'runs': [
                                              {'text': 'Song • Fat Papi • 99M plays'}
                                            ]
                                          }
                                        }
                                      },
                                    ],
                                    'overlay': {
                                      'musicItemThumbnailOverlayRenderer': {
                                        'content': {
                                          'musicPlayButtonRenderer': {
                                            'playNavigationEndpoint': {
                                              'watchEndpoint': {
                                                'videoId': 'ytm-song-1',
                                                'watchEndpointMusicSupportedConfigs': {
                                                  'watchEndpointMusicConfig': {
                                                    'musicVideoType': 'MUSIC_VIDEO_TYPE_ATV'
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    },
                                  }
                                }
                              ]
                            }
                          }
                        ]
                      }
                    }
                  }
                }
              ]
            }
          }
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final ytm = YtMusicInnerTube(client: client);
    final res = await ytm.search('freaked out', addonId: 'com.beatboss.ytmusic');

    expect(res.tracks.map((t) => t.id), ['ytm-song-1', 'top-vid', 'yt-1']);
    expect(
      res.tracks.first.artworkURL,
      'https://lh3.googleusercontent.com/abc=w1200-h1200-l90-rj',
    );
  });
}

