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
        externals: {
            axios: 'axios'
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
        // hot: true,
        static: {
            directory: __dirname + 'public',
            publicPath: '/'
        },
        headers: {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, PATCH, OPTIONS",
            "Access-Control-Allow-Headers": "X-Requested-With, content-type, Authorization"
        }
    }

    return isDevServer ? {...appConfig, devServer} : appConfig;
}

