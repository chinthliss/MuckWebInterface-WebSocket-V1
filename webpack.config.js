import * as url from 'url';
// const __filename = url.fileURLToPath(import.meta.url);
const __dirname = url.fileURLToPath(new URL('.', import.meta.url));

export default function config(args, options) {
    const isProduction = options.mode === "production";
    const isDevServer = process.argv.includes("serve");

    const appConfig = {
        entry: __dirname + '/src/index.js',
        mode: isProduction ? "production" : "development",
        experiments: {outputModule: true},
        module: {
            rules: [
                {
                    test: /\.js$/,
                    exclude: /node_modules/,
                    use: {
                        loader: "babel-loader"
                    }
                }
            ]
        },
        output: {
            path: __dirname + "dist/",
            filename: 'mwi-websocket.js',
            library: {
                type: 'module'
            }
        }
    };

    const devServer = {
        port: 9000,
        headers: {
            'Access-Control-Allow-Origin': '*'
        }
    }

    return isDevServer ? {...appConfig, devServer} : appConfig;
}

