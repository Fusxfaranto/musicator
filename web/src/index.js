// -*- mode: js-jsx -*-

import AceEditor from "react-ace-builds";
import React, { useRef, useEffect, useState } from 'react';
//import Konva from 'konva';
import { render } from 'react-dom';
import { Circle, Stage, Layer, Line } from 'react-konva';


import 'ace-builds/src-noconflict/mode-c_cpp';
import 'ace-builds/src-noconflict/theme-github';

import './index.css';


Math.clamp = function(number, min, max) {
    return Math.max(min, Math.min(number, max));
};


// TODO note input by simultaneously tapping out beat and playing notes, with configurable snap intervals (which will require having tempo integration)

const Foo = props => {
    const [state, setState] = useState({
        x: 50,
        y: 50
    });

    const [dragging, setDragging] = useState(false);

    return (
        <Circle
          x={state.x}
          y={state.y}
          radius={10}
          draggable
          fill={dragging ? 'green' : 'red'}
          // TODO setting onMouseDown seems to cause problems
          onMouseDown={() => {
              setDragging(true);
          }}
          onMouseUp={() => {
              setDragging(false);
          }}
          onDragEnd={e => {
              console.log(e.target.x(), e.target.y());
              setState({
                  x: e.target.x(),
                  y: e.target.y()
              });
          }}
          /* onDragMove={e => { */
          /*     //console.log(e); */
          /* }} */
          dragBoundFunc={pos => {
              //console.log(pos);
              return {
                  x: Math.clamp(pos.x, 0, props.stageWidth),
                  y: Math.clamp(pos.y, 0, props.stageHeight),
              };
          }}
          />);
};

const GridDir = Object.freeze({
    v: Symbol("GridDir.v"),
    h: Symbol("GridDir.h"),
});

const Grid = props => {
    let elems = [];
    let to = (() => {
        switch (props.dir) {
        case GridDir.v:
            return props.width;
        case GridDir.h:
            return props.height;
        default:
            return null;
        }
    })();
    for (let i = 0; i < to; i += props.span) {
        let points = (() => {
            switch (props.dir) {
            case GridDir.v:
                return [i, 0, i, props.height];
            case GridDir.h:
                return [0, i, props.width, i];
            default:
                return null;
            }
        })();
        elems.push(<Line
                   points={points}
                   stroke='gray'
                   strokeWidth={1}
                   // TODO ??
                   key={i}
                   />);
    }

    return (
        <>
          {elems}
        </>
    );
};

const Chart = props => {
    const ref = useRef();
    const [dim, setDim] = useState({
        width: 0,
        height: 0,
    });
    const [skipStage, setSkipStage] = useState(true);

    const autoSetDim = () => {
        if (ref.current) {
            setDim({
                width: ref.current.offsetWidth,
                height: ref.current.offsetHeight,
            });
        }
    };

    useEffect(() => {
        autoSetDim();
        setSkipStage(false);
    }, []);

    useEffect(() => {
        let resize_timer = null;
        const handler = () => {
            clearInterval(resize_timer);
            autoSetDim();
            setSkipStage(true);
            resize_timer = setTimeout(() => { setSkipStage(false); }, 200);
        };

        window.addEventListener('resize', handler);

        return () => window.removeEventListener('resize', handler);
    }, []);

    const stageW = dim.width;// - 100;
    const stageH = dim.height;// - 100;

    return (
        <div
          className="chart-container"
          ref={ref}
          >
          { !skipStage &&
              <Stage width={stageW} height={stageH}>
                    <Layer>
                          <Grid
                                width={stageW}
                                height={stageH}
                                dir={GridDir.v}
                                span={50}
                                />
                              <Grid
                                    width={stageW}
                                    height={stageH}
                                    dir={GridDir.h}
                                    span={50}
                                    />
                                  <Foo
                                        stageWidth={stageW}
                                        stageHeight={stageH}
                                        />
                        </Layer>
                  </Stage>
              }
        </div>
    );
};


const ProgMenuEntry = props => {
    //const [hideVars, setHideVars] = useState(false);
    const hideVars = props.hideVars;

    const arrow = hideVars ? '>' : 'V';

    const prog = props.prog;

    const varsList = hideVars ? null :
          <ul className="prog-menu-list">
          {prog.locals.map((local =>
                            <li key={local.name}> {local.name} {local.type} </li>
                           ))}
    </ul>;
    
    return (
        <>
          <li>
            <div onClick={props.onClick}>
              {arrow}
              &nbsp;
              {prog.name}
            </div>

            {varsList}
          </li>
        </>
    );
};

const CodeInput = props => {
    return (
        <AceEditor
          className={props.className}
          mode="c_cpp"
          theme="github"
          value={props.contents}
          onChange={props.onChange}
          name={props.name}
          // editorProps={{ $blockScrolling: true }}
          />);
}

const ProgInput = props => {
    return (
        <CodeInput
          className="prog-menu-input"
          contents={props.unselected ? "" : props.contents}
          onChange={props.onChange}
          name={props.name}
          />
    );
};

const ProgMenu = props => {
    const [showIdx, setShowIdx] = useState(-1);

    const noneSelected = showIdx === -1;
    const selectedProg = noneSelected ? null : props.progs[showIdx];
    const selectedContents = noneSelected ? null : selectedProg.prog;
    //console.log(selectedContents);

    const handleChangeTo = (i) => () => {
        if (i !== showIdx) {
            setShowIdx(i);
        } else {
            setShowIdx(-1);
        }
    };
    
    return (
        <>

          <ProgInput
            name="main-prog-input"
            contents={selectedContents}
            unselected={noneSelected}
            onChange={(value) => {
                if (noneSelected) {
                    //setProgInputContents("");
                } else {
                    //setProgInputContents(value);
                    props.setProgContents(showIdx, value);
                }
            }}
            />

            <ul className="prog-menu-list">
              {props.progs.map(
                  ((prog, i) =>
                   <ProgMenuEntry
                         prog={prog}
                         key={prog.name}
                         hideVars={i !== showIdx}
                         onClick={handleChangeTo(i)}
                         />)
              )}
        </ul>
            </>
    );
};

const NumInput = props => {
    const [inputState, setInputState] = useState(null);

    if (props.stateVal && inputState === null) {
        setInputState(props.stateVal);
    }

    //console.log(props.stateVal);
    console.log(inputState);
    return (
        <input
          type="number"
          value={inputState === null ? '' : inputState}
          onChange={(e) => {
              const value = e.currentTarget.value;
              //console.log(value);
              setInputState(value);
              if (value > 0) {
                  props.updateState(parseInt(value));
              }
              //return value;
          }}
          />
    );
}

const App = props => {
    const [state, setState] = useState({
        progs: [],
    });

    const [shouldUpdate, setShouldUpdate] = useState(false);

    const ws = props.ws;
    ws.onopen = () => {
        console.log('websocket connected');

        ws.send(JSON.stringify({
            type: "getstate",
            contents: null,
        }));
    }

    ws.onmessage = evt => {
        const message = JSON.parse(evt.data);
        console.log(message);

        switch (message.type) {
        case 'set':
            setState(message.contents);
            break;

        default:
            console.error("bad message type");
        }
    }

    ws.onclose = () => {
        console.log('websocket disconnected');
    }

    let progs = state.progs;

    const setProgContents = (i, contents) => {
        //console.log(i);
        //console.log(contents);

        if (progs[i].prog !== contents) {
            progs[i].prog = contents;
            setState({
                ...state,
                progs: progs,
            })

            setShouldUpdate(true);
        } else {
            console.error("???");
        }
    };

    useEffect(() => {
        // TODO something more efficient
        if (!shouldUpdate) {
            return;
        }

        ws.send(JSON.stringify(
            {
                type: "setstate",
                contents: state,
            }
        ));

        setShouldUpdate(false);
    }, [shouldUpdate, state, ws]);

    return (
        <div className="app-container">
          <div className="menu-container">
            <ProgMenu
              progs={progs}
              setProgContents={setProgContents}
              />
          </div>
          <div className="app-side-container">
            <div className="other-container">

              <CodeInput
                className="prog-helper-input"
                contents={state.prog_helpers}
                onChange={(value) => {
                    setState({
                        ...state,
                        prog_helpers: value,
                    })
                    setShouldUpdate(true);
                }}
                />

                <button onClick={() => {
                      ws.send(JSON.stringify(
                          {
                              type: "save",
                              contents: {
                                  // TODO
                                  filename: "state.json",
                              },
                          }
                      ));}
                  }>
                  Save
                </button>

                <button onClick={() => {
                      ws.send(JSON.stringify(
                          {
                              type: "load",
                              contents: {
                                  // TODO
                                  filename: "state.json",
                              },
                          }
                      ));}
                  }>
                  Load
                </button>

                <br />
                <br />

                <button onClick={() => {
                      ws.send(JSON.stringify(
                          {
                              type: "pause",
                              contents: null,
                          }
                      ));}
                  }>
                  Pause
                </button>

                <button onClick={() => {
                      ws.send(JSON.stringify(
                          {
                              type: "play",
                              contents: null,
                          }
                      ));}
                  }>
                  Play
                </button>


                <NumInput
                  stateVal={state.snap_denominator}
                  updateState={(value) => {
                      setState({
                          ...state,
                          snap_denominator: value,
                      })
                      setShouldUpdate(true);
                  }}
                  />
                <NumInput
                  stateVal={state.tempo}
                  updateState={(value) => {
                      setState({
                          ...state,
                          tempo: value,
                      })
                      setShouldUpdate(true);
                  }}
                  />
            </div>
            <Chart />
          </div>
        </div>
    );
};

const ws = new WebSocket('ws://127.0.0.1:3001');
render(<App ws={ws} />, document.getElementById('root'));
